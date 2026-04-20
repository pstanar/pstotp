using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using PsTotp.Server.Infrastructure.Data;

namespace PsTotp.Server.Api.EndPoints;

public static class AuditEndpoints
{
    public static async Task<IResult> GetAuditEvents(
        ClaimsPrincipal user,
        AppDbContext db,
        int? limit)
    {
        var userId = Guid.Parse(
            user.FindFirstValue(ClaimTypes.NameIdentifier)
            ?? throw new UnauthorizedAccessException());

        var take = Math.Min(limit ?? 50, 200);

        var events = await db.AuditEvents
            .Where(e => e.UserId == userId)
            .OrderByDescending(e => e.CreatedAt)
            .Take(take)
            .Select(e => new
            {
                e.Id,
                e.EventType,
                e.EventData,
                e.IpAddress,
                e.CreatedAt,
                e.DeviceId,
            })
            .ToListAsync();

        return Results.Ok(new { Events = events });
    }
}
