namespace PsTotp.Server.Application.Services;

/// <summary>
/// Runtime-toggleable server settings managed from the admin UI.
/// Backed by a singleton DB row so changes take effect without a
/// restart and survive across instances.
/// </summary>
public interface IServerSettingsService
{
    Task<ServerSettingsSnapshot> GetAsync(CancellationToken ct = default);
    Task<ServerSettingsSnapshot> SetRegistrationEnabledAsync(bool enabled, CancellationToken ct = default);
}

/// <summary>
/// Plain DTO so endpoints / callers don't take a dependency on the
/// domain entity. UpdatedAt lets the admin UI show "last changed at".
/// </summary>
public sealed record ServerSettingsSnapshot(bool RegistrationEnabled, DateTime UpdatedAt);
