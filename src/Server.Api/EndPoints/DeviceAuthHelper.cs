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

    public static async Task<Device?> GetApprovedCallerDevice(ClaimsPrincipal user, AppDbContext db)
    {
        var userId = GetUserId(user);
        var deviceId = GetDeviceId(user);
        return await db.Devices.FirstOrDefaultAsync(d =>
            d.Id == deviceId && d.UserId == userId && d.Status == DeviceStatus.Approved);
    }
}
