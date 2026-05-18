namespace PsTotp.Server.Domain.Entities;

/// <summary>
/// Server-wide settings the operator can toggle at runtime from the
/// admin UI. Singleton row — one record per install. Lives in the DB
/// (not appsettings.json) so changes take effect without a restart
/// and so the operator gets an audit trail via IAuditService.
///
/// New runtime settings should land here as additional columns rather
/// than as separate tables, so the singleton row + service stay
/// trivially queryable as one shot.
/// </summary>
public class ServerSettings
{
    /// <summary>
    /// Singleton primary key. The application enforces "exactly one
    /// row" via <see cref="SingletonId"/>.
    /// </summary>
    public Guid Id { get; set; }

    /// <summary>
    /// When false, <c>/auth/register/begin</c> returns 403 and no new
    /// users can self-register. Operator toggles this from the admin
    /// UI; effect is immediate (no restart). Default true on first
    /// install / migration so existing deployments aren't disturbed.
    /// </summary>
    public bool RegistrationEnabled { get; set; }

    public DateTime UpdatedAt { get; set; }

    /// <summary>
    /// Stable PK for the singleton row. All access goes through this
    /// fixed Guid so the row is trivially findable + idempotently
    /// seedable across providers.
    /// </summary>
    public static readonly Guid SingletonId =
        new("00000000-0000-0000-0000-000000000001");
}
