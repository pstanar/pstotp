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

    public static async Task<bool> IsDeviceApproved(ClaimsPrincipal user, AppDbContext db)
    {
        var deviceClaim = user.FindFirstValue(Application.SharedConstants.DeviceIdClaim);
        if (deviceClaim is null || !Guid.TryParse(deviceClaim, out var deviceId))
            return false;

        var device = await db.Devices.FirstOrDefaultAsync(d => d.Id == deviceId);
        return device?.Status == DeviceStatus.Approved;
    }

    public static async Task<Device?> GetApprovedCallerDevice(ClaimsPrincipal user, AppDbContext db)
    {
        var userId = GetUserId(user);
        var deviceId = GetDeviceId(user);
        return await db.Devices.FirstOrDefaultAsync(d =>
            d.Id == deviceId && d.UserId == userId && d.Status == DeviceStatus.Approved);
    }
}
