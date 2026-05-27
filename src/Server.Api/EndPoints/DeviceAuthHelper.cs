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

    private static bool TryGetUserId(ClaimsPrincipal user, out Guid userId)
    {
        var sub = user.FindFirstValue(ClaimTypes.NameIdentifier);
        if (sub is not null && Guid.TryParse(sub, out userId))
            return true;
        userId = default;
        return false;
    }

    private static bool TryGetDeviceId(ClaimsPrincipal user, out Guid deviceId)
    {
        var deviceClaim = user.FindFirstValue(Application.SharedConstants.DeviceIdClaim);
        if (deviceClaim is not null && Guid.TryParse(deviceClaim, out deviceId))
            return true;
        deviceId = default;
        return false;
    }

    /// <summary>
    /// Reject the request if the caller's device isn't in
    /// <see cref="DeviceStatus.Approved"/>. Distinguishes:
    /// <list type="bullet">
    ///   <item>
    ///     <description>
    ///     <b>Claims missing/malformed or device row missing for this
    ///     user</b>: <b>401 Unauthorized</b>. The JWT references a
    ///     device that doesn't belong to the authenticated user (or
    ///     doesn't exist at all) — typically a stale cookie pointing
    ///     at a deleted account or a fresh DB. Returning 401 lets the
    ///     SPA's refresh-and-retry interceptor fail through to the
    ///     login screen and clear the dead cookie, instead of looping
    ///     on opaque 403s until the access token expires.
    ///     </description>
    ///   </item>
    ///   <item>
    ///     <description>
    ///     <b>Device row exists for this user but is not Approved</b>
    ///     (Pending, Rejected, Revoked): <b>403 Forbidden</b>. The
    ///     session is real; the device just hasn't been authorised
    ///     yet (or has been revoked). The client should surface
    ///     "approve me from another device" rather than
    ///     re-authenticating.
    ///     </description>
    ///   </item>
    /// </list>
    /// Returns <c>null</c> when the caller is fully authorised — the
    /// pattern in callers is
    /// <c>if (await RejectIfDeviceNotApproved(...) is { } r) return r;</c>.
    /// The device-belongs-to-user binding is checked at the DB query
    /// so a JWT carrying someone else's device_id can't pass this
    /// gate.
    /// </summary>
    public static async Task<IResult?> RejectIfDeviceNotApproved(ClaimsPrincipal user, AppDbContext db)
    {
        if (!TryGetUserId(user, out var userId) || !TryGetDeviceId(user, out var deviceId))
            return Results.Unauthorized();

        var device = await db.Devices.FirstOrDefaultAsync(d => d.Id == deviceId && d.UserId == userId);
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
    /// session metadata, etc.) don't re-query.
    /// <code>
    /// var (rejection, device) = await DeviceAuthHelper.AuthoriseCallerDevice(user, db);
    /// if (rejection is not null) return rejection;
    /// // device is non-null here.
    /// </code>
    /// </summary>
    public static async Task<(IResult? Rejection, Device? Device)> AuthoriseCallerDevice(
        ClaimsPrincipal user, AppDbContext db)
    {
        if (!TryGetUserId(user, out var userId) || !TryGetDeviceId(user, out var deviceId))
            return (Results.Unauthorized(), null);

        var device = await db.Devices.FirstOrDefaultAsync(d => d.Id == deviceId && d.UserId == userId);
        if (device is null)
            return (Results.Unauthorized(), null);

        return device.Status == DeviceStatus.Approved
            ? (null, device)
            : (Results.Forbid(), null);
    }
}
