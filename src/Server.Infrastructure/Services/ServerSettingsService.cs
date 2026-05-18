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
        row = new ServerSettings
        {
            Id = ServerSettings.SingletonId,
            RegistrationEnabled = true,
            UpdatedAt = DateTime.UtcNow,
        };
        db.ServerSettings.Add(row);
        await db.SaveChangesAsync(ct);
        return row;
    }
}
