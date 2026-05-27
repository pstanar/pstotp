using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using PsTotp.Server.Domain.Entities;
using PsTotp.Server.Infrastructure.Data;

namespace PsTotp.Server.Api.EndPoints;

public static class DeviceAuthHelper
{
    public static Guid GetUserId(ClaimsPrincipal user)
    {
        var sub = user.FindFirstValue(ClaimTypes.NameIdentifier)
                  ?? throw new UnauthorizedAccessException();
        return Guid.Parse(sub);
    }

    public static Guid GetDeviceId(ClaimsPrincipal user)
    {
        var deviceClaim = user.FindFirstValue(Application.SharedConstants.DeviceIdClaim)
                          ?? throw new UnauthorizedAccessException();
        return Guid.Parse(deviceClaim);
    }

    /// <summary>
    /// Reject the request if the caller's device isn't in
    /// <see cref="DeviceStatus.Approved"/>. Distinguishes two cases:
    /// <list type="bullet">
    ///   <item>
    ///     <description>
    ///     <b>Device row missing</b> (or device_id claim missing/malformed):
    ///     <b>401 Unauthorized</b>. The JWT references a device that no
    ///     longer exists — typically a stale cookie pointing at a deleted
    ///     account or a fresh DB. Returning 401 lets the SPA's refresh-
    ///     and-retry interceptor fail through to the login screen and
    ///     clear the dead cookie, instead of looping on opaque 403s
    ///     until the access token finally expires.
    ///     </description>
    ///   </item>
    ///   <item>
    ///     <description>
    ///     <b>Device row exists but not Approved</b> (Pending, Rejected,
    ///     Revoked): <b>403 Forbidden</b>. The session is real; the
    ///     device just hasn't been authorised yet (or has been revoked).
    ///     The client should surface "approve me from another device"
    ///     rather than re-authenticating.
    ///     </description>
    ///   </item>
    /// </list>
    /// Returns <c>null</c> when the caller is fully authorised — the
    /// pattern in callers is
    /// <c>if (await RejectIfDeviceNotApproved(...) is { } r) return r;</c>.
    /// </summary>
    public static async Task<IResult?> RejectIfDeviceNotApproved(ClaimsPrincipal user, AppDbContext db)
    {
        var deviceClaim = user.FindFirstValue(Application.SharedConstants.DeviceIdClaim);
        if (deviceClaim is null || !Guid.TryParse(deviceClaim, out var deviceId))
            return Results.Unauthorized();

        var device = await db.Devices.FirstOrDefaultAsync(d => d.Id == deviceId);
        if (device is null)
            return Results.Unauthorized();

        return device.Status == DeviceStatus.Approved
            ? null
            : Results.Forbid();
    }

    /// <summary>
    /// Same 401/403 distinction as
    /// <see cref="RejectIfDeviceNotApproved(ClaimsPrincipal, AppDbContext)"/>,
    /// but returns the resolved <see cref="Device"/> on success so callers
    /// that need the row (envelope updates, passkey registration, recovery
    /// session metadata, etc.) don't re-query. The contract:
    /// <list type="bullet">
    ///   <item><description>
    ///     Returns <c>(null, device)</c> when the caller is authorised.
    ///   </description></item>
    ///   <item><description>
    ///     Returns <c>(401, null)</c> when the device claim is
    ///     missing/malformed or the row isn't in the DB (stale JWT against
    ///     a deleted/recreated account).
    ///   </description></item>
    ///   <item><description>
    ///     Returns <c>(403, null)</c> when the row exists but isn't
    ///     <see cref="DeviceStatus.Approved"/>.
    ///   </description></item>
    /// </list>
    /// Caller pattern:
    /// <code>
    /// var (rejection, device) = await DeviceAuthHelper.AuthoriseCallerDevice(user, db);
    /// if (rejection is not null) return rejection;
    /// // device is non-null here.
    /// </code>
    /// </summary>
    public static async Task<(IResult? Rejection, Device? Device)> AuthoriseCallerDevice(
        ClaimsPrincipal user, AppDbContext db)
    {
        var deviceClaim = user.FindFirstValue(Application.SharedConstants.DeviceIdClaim);
        if (deviceClaim is null || !Guid.TryParse(deviceClaim, out var deviceId))
            return (Results.Unauthorized(), null);

        var userId = GetUserId(user);
        var device = await db.Devices.FirstOrDefaultAsync(d => d.Id == deviceId && d.UserId == userId);
        if (device is null)
            return (Results.Unauthorized(), null);

        return device.Status == DeviceStatus.Approved
            ? (null, device)
            : (Results.Forbid(), null);
    }
}
