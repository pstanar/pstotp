using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using PsTotp.Server.Infrastructure.Data;

namespace PsTotp.Server.Api.Filters;

/// <summary>
/// Enforces account-level policies on protected endpoints:
/// - Disabled accounts are rejected (403)
/// - ForcePasswordReset blocks all endpoints except password change (403)
/// </summary>
public class AccountStatusFilter : IEndpointFilter
{
    // Only password change is exempt — refresh/logout are public endpoints and don't hit this filter
    private static readonly HashSet<string> PasswordChangeAllowedPaths =
    [
        "/api/account/password/change",
    ];

    public async ValueTask<object?> InvokeAsync(EndpointFilterInvocationContext context, EndpointFilterDelegate next)
    {
        var httpContext = context.HttpContext;
        var userIdClaim = httpContext.User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
            return await next(context);

        var db = httpContext.RequestServices.GetRequiredService<AppDbContext>();
        var user = await db.Users
            .AsNoTracking()
            .Where(u => u.Id == userId)
            .Select(u => new { u.DisabledAt, u.ForcePasswordReset })
            .FirstOrDefaultAsync();

        if (user is null)
            return await next(context);

        if (user.DisabledAt.HasValue)
            return Results.Json(new { Error = AuthConstants.ErrorAccountDisabled }, statusCode: 403);

        if (user.ForcePasswordReset)
        {
            var path = httpContext.Request.Path.Value?.ToLowerInvariant() ?? "";
            if (!PasswordChangeAllowedPaths.Contains(path))
                return Results.Json(new { Error = AuthConstants.ErrorPasswordResetRequired }, statusCode: 403);
        }

        return await next(context);
    }
}
