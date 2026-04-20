using PsTotp.Server.Application.DTOs;
using PsTotp.Server.Application.Services;
using PsTotp.Server.Infrastructure.Data;

namespace PsTotp.Server.Api.EndPoints;

public static class TokenEndpoints
{
    public static async Task<IResult> Refresh(
        RefreshRequest request,
        ITokenService tokenService,
        HttpContext httpContext)
    {
        var refreshToken = GetRefreshTokenFromCookieOrBody(httpContext, request);
        if (string.IsNullOrEmpty(refreshToken))
            return Results.Unauthorized();

        var result = await tokenService.RotateRefreshTokenAsync(refreshToken);
        if (result is null)
            return Results.Unauthorized();

        // Detect web client by the refresh-token cookie (not access-token — it's expired at refresh time)
        var isWeb = httpContext.Request.Cookies.ContainsKey(AuthConstants.RefreshTokenCookieName);
        if (isWeb)
            LoginHelper.SetTokenCookies(httpContext, result.Value.accessToken, result.Value.refreshToken);

        return Results.Ok(new RefreshResponse(
            isWeb ? null : result.Value.accessToken,
            isWeb ? null : result.Value.refreshToken));
    }

    public static async Task<IResult> Logout(
        RefreshRequest request,
        ITokenService tokenService,
        AppDbContext db,
        HttpContext httpContext)
    {
        var refreshToken = GetRefreshTokenFromCookieOrBody(httpContext, request);
        if (!string.IsNullOrEmpty(refreshToken))
        {
            await tokenService.RevokeRefreshTokenAsync(refreshToken);
            await db.SaveChangesAsync();
        }

        LoginHelper.ClearTokenCookies(httpContext);
        return Results.Ok();
    }

    private static string? GetRefreshTokenFromCookieOrBody(HttpContext httpContext, RefreshRequest request)
    {
        if (httpContext.Request.Cookies.TryGetValue(AuthConstants.RefreshTokenCookieName, out var cookieToken)
            && !string.IsNullOrEmpty(cookieToken))
            return cookieToken;

        return request.RefreshToken;
    }
}
