using System.Security.Claims;
using PsTotp.Server.Application.Services;
using PsTotp.Server.Infrastructure.Data;

namespace PsTotp.Server.Api.EndPoints;

/// <summary>
/// Admin endpoints for runtime-toggleable server settings. Backed by
/// the singleton <c>ServerSettings</c> row via
/// <see cref="IServerSettingsService"/>. Wired under the
/// AdminPolicy-gated route group in <c>Routes.cs</c>.
/// </summary>
public static class AdminSettingsEndpoints
{
    public sealed record SettingsResponse(bool RegistrationEnabled, string UpdatedAt);

    public sealed record SetRegistrationEnabledRequest(bool Enabled);

    public static async Task<IResult> Get(
        IServerSettingsService serverSettings,
        HttpContext httpContext)
    {
        var snap = await serverSettings.GetAsync(httpContext.RequestAborted);
        return Results.Ok(new SettingsResponse(
            snap.RegistrationEnabled,
            snap.UpdatedAt.ToString("O")));
    }

    public static async Task<IResult> SetRegistrationEnabled(
        SetRegistrationEnabledRequest request,
        ClaimsPrincipal principal,
        AppDbContext db,
        IServerSettingsService serverSettings,
        IAuditService audit,
        HttpContext httpContext)
    {
        var adminId = DeviceAuthHelper.GetUserId(principal);
        var snap = await serverSettings.SetRegistrationEnabledAsync(
            request.Enabled, httpContext.RequestAborted);

        // Audit on every toggle (including no-op flips to the same
        // value) — the audit log answers "who turned this off and
        // when" without needing a separate change-detection step.
        // LogEvent only stages the event; SaveChangesAsync below
        // persists it.
        audit.LogEvent(AuditEvents.RegistrationEnabledChanged, adminId,
            eventData: new { snap.RegistrationEnabled, ChangedBy = adminId },
            ipAddress: httpContext.Connection.RemoteIpAddress?.ToString());
        await db.SaveChangesAsync(httpContext.RequestAborted);

        return Results.Ok(new SettingsResponse(
            snap.RegistrationEnabled,
            snap.UpdatedAt.ToString("O")));
    }
}
