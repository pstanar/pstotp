using Microsoft.EntityFrameworkCore;
using PsTotp.Server.Application.Services;
using PsTotp.Server.Domain.Entities;
using PsTotp.Server.Infrastructure.Data;

namespace PsTotp.Server.Infrastructure.Services;

/// <summary>
/// EF-backed runtime-settings service. One row, fetched / updated by
/// the singleton key. The seed in <c>AppDbContext.OnModelCreating</c>
/// guarantees the row exists after migration; the defensive read-or-
/// create path here covers older installs that may have been built
/// before the seed or where the row was somehow deleted.
/// </summary>
public sealed class ServerSettingsService(AppDbContext db) : IServerSettingsService
{
    public async Task<ServerSettingsSnapshot> GetAsync(CancellationToken ct = default)
    {
        var row = await LoadOrCreateAsync(ct);
        return new ServerSettingsSnapshot(row.RegistrationEnabled, row.UpdatedAt);
    }

    public async Task<ServerSettingsSnapshot> SetRegistrationEnabledAsync(bool enabled, CancellationToken ct = default)
    {
        var row = await LoadOrCreateAsync(ct);
        row.RegistrationEnabled = enabled;
        row.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);
        return new ServerSettingsSnapshot(row.RegistrationEnabled, row.UpdatedAt);
    }

    private async Task<ServerSettings> LoadOrCreateAsync(CancellationToken ct)
    {
        var row = await db.ServerSettings.FirstOrDefaultAsync(s => s.Id == ServerSettings.SingletonId, ct);
        if (row is not null) return row;

        // Defensive creation — should be unreachable on a properly
        // migrated install. Registration defaults to enabled so we
        // don't surprise existing deployments.
        //
        // Two concurrent callers can both observe "no row" and both try
        // to insert SingletonId; the primary key collision will fail
        // exactly one of them. Catch that and re-read so the loser
        // returns the winner's row instead of bubbling the exception.
        row = new ServerSettings
        {
            Id = ServerSettings.SingletonId,
            RegistrationEnabled = true,
            UpdatedAt = DateTime.UtcNow,
        };
        db.ServerSettings.Add(row);
        try
        {
            await db.SaveChangesAsync(ct);
            return row;
        }
        catch (DbUpdateException ex) when (IsDuplicateKeyViolation(ex))
        {
            db.Entry(row).State = EntityState.Detached;
            var winner = await db.ServerSettings.FirstOrDefaultAsync(s => s.Id == ServerSettings.SingletonId, ct);
            if (winner is not null) return winner;
            throw;
        }
    }

    /// <summary>
    /// True iff the failure is a primary-key / unique-index collision
    /// from one of the four providers we support. Everything else
    /// (connection drop, timeout, missing table, schema drift, disk
    /// full) bubbles up — we never want to silently treat those as
    /// "someone else won the race." Detection is via reflection on
    /// the provider-specific inner exception so this assembly stays
    /// free of provider package dependencies.
    /// </summary>
    private static bool IsDuplicateKeyViolation(DbUpdateException ex)
    {
        var inner = ex.InnerException;
        if (inner is null) return false;

        switch (inner.GetType().FullName)
        {
            // PostgreSQL: SQLSTATE 23505 = unique_violation.
            case "Npgsql.PostgresException":
                return ReadProperty<string>(inner, "SqlState") == "23505";

            // SQL Server: 2627 = PK violation, 2601 = unique-index violation.
            case "Microsoft.Data.SqlClient.SqlException":
                {
                    var n = ReadProperty<int?>(inner, "Number");
                    return n is 2627 or 2601;
                }

            // MySQL / MariaDB: 1062 = ER_DUP_ENTRY.
            case "MySqlConnector.MySqlException":
                return ReadProperty<int?>(inner, "Number") is 1062;

            // SQLite: extended codes 1555 (PK) / 2067 (UNIQUE). Match
            // the extended codes only, not the bare 19 = SQLITE_
            // CONSTRAINT, so NOT NULL / FK / CHECK failures don't get
            // treated as race losses.
            case "Microsoft.Data.Sqlite.SqliteException":
                return ReadProperty<int?>(inner, "SqliteExtendedErrorCode") is 1555 or 2067;

            default:
                return false;
        }
    }

    private static T? ReadProperty<T>(object source, string name)
    {
        var value = source.GetType().GetProperty(name)?.GetValue(source);
        return value is T typed ? typed : default;
    }
}
