using Microsoft.EntityFrameworkCore;
using PsTotp.Server.Application.DTOs;
using PsTotp.Server.Domain.Entities;
using PsTotp.Server.Infrastructure.Data;

namespace PsTotp.Server.Api.EndPoints;

/// <summary>
/// Shared login orchestration: device matching, envelope retrieval, cookie setting, response building.
/// Used by both password login (AuthEndpoints) and passkey login (WebAuthnAssertionEndpoints).
/// </summary>
public static class LoginHelper
{
    public static bool IsWebClient(string? clientType) =>
        string.Equals(clientType, AuthConstants.WebClientType, StringComparison.OrdinalIgnoreCase);

    /// <summary>
    /// Match an existing device by ECDH public key, or create a new pending device.
    /// </summary>
    public static async Task<Device?> MatchOrCreateDevice(
        AppDbContext db, Guid userId, DeviceDto deviceDto)
    {
        Device? device = null;
        if (!string.IsNullOrEmpty(deviceDto.DevicePublicKey))
        {
            device = await db.Devices.FirstOrDefaultAsync(d =>
                d.UserId == userId && d.DevicePublicKey == deviceDto.DevicePublicKey
                && d.Status != DeviceStatus.Revoked);

            device?.DeviceName = deviceDto.DeviceName;
        }

        if (device is null)
        {
            device = new Device
            {
                Id = Guid.NewGuid(),
                UserId = userId,
                DeviceName = deviceDto.DeviceName,
                Platform = deviceDto.Platform,
                ClientType = deviceDto.ClientType,
                DevicePublicKey = deviceDto.DevicePublicKey,
                Status = DeviceStatus.Pending,
                CreatedAt = DateTime.UtcNow,
            };
            db.Devices.Add(device);
        }

        return device;
    }

    /// <summary>
    /// Fetch password and device envelopes for an approved device.
    /// </summary>
    public static async Task<LoginEnvelopes> GetLoginEnvelopes(
        AppDbContext db, Guid userId, Device device)
    {
        var passwordEnvelope = await db.VaultKeyEnvelopes.FirstOrDefaultAsync(e =>
            e.UserId == userId && e.EnvelopeType == EnvelopeType.Password && e.RevokedAt == null);

        VaultKeyEnvelope? deviceEnvelope = null;
        if (!string.IsNullOrEmpty(device.DevicePublicKey))
        {
            deviceEnvelope = await db.VaultKeyEnvelopes.FirstOrDefaultAsync(e =>
                e.UserId == userId && e.DeviceId == device.Id
                && e.EnvelopeType == EnvelopeType.Device && e.RevokedAt == null);
        }

        return new LoginEnvelopes(
            passwordEnvelope != null ? EnvelopeHelper.FromBytes(passwordEnvelope.WrappedKeyPayload) : null,
            deviceEnvelope != null ? EnvelopeHelper.FromBytes(deviceEnvelope.WrappedKeyPayload) : null);
    }

    /// <summary>
    /// Set httpOnly token cookies for web clients.
    /// </summary>
    public static void SetTokenCookies(HttpContext httpContext, string accessToken, string refreshToken)
    {
        httpContext.Response.Cookies.Append(AuthConstants.AccessTokenCookieName, accessToken, new CookieOptions
        {
            HttpOnly = true, Secure = true, SameSite = SameSiteMode.Strict,
            Path = "/", MaxAge = TimeSpan.FromMinutes(15),
        });
        httpContext.Response.Cookies.Append(AuthConstants.RefreshTokenCookieName, refreshToken, new CookieOptions
        {
            HttpOnly = true, Secure = true, SameSite = SameSiteMode.Strict,
            Path = AuthConstants.RefreshTokenCookiePath, MaxAge = TimeSpan.FromDays(30),
        });
    }

    /// <summary>
    /// Clear token cookies on logout.
    /// </summary>
    public static void ClearTokenCookies(HttpContext httpContext)
    {
        // __Host- cookies require Secure on every Set-Cookie, including deletion
        httpContext.Response.Cookies.Delete(AuthConstants.AccessTokenCookieName, new CookieOptions
        {
            Path = "/", Secure = true, HttpOnly = true, SameSite = SameSiteMode.Strict,
        });
        httpContext.Response.Cookies.Delete(AuthConstants.RefreshTokenCookieName, new CookieOptions
        {
            Path = AuthConstants.RefreshTokenCookiePath, Secure = true, HttpOnly = true, SameSite = SameSiteMode.Strict,
        });
    }

    /// <summary>
    /// Build the standard login response, setting cookies for web clients.
    /// </summary>
    public static LoginCompleteResponse BuildLoginResponse(
        HttpContext httpContext, Guid userId, Device device,
        string accessToken, string refreshToken,
        LoginEnvelopes? envelopes, Guid? approvalRequestId,
        string? role = null, bool forcePasswordReset = false)
    {
        var isWeb = IsWebClient(device.ClientType);
        if (isWeb)
            SetTokenCookies(httpContext, accessToken, refreshToken);

        return new LoginCompleteResponse(
            userId,
            isWeb ? null : accessToken,
            isWeb ? null : refreshToken,
            new LoginDeviceInfo(device.Id, device.Status.ToString().ToLowerInvariant(), device.Status == DeviceStatus.Approved),
            envelopes,
            approvalRequestId,
            role,
            forcePasswordReset);
    }
}
