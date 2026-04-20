using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using PsTotp.Server.Application.Crypto;
using PsTotp.Server.Application.DTOs;
using PsTotp.Server.Application.Services;
using PsTotp.Server.Domain.Entities;
using PsTotp.Server.Infrastructure.Data;

namespace PsTotp.Server.Api.EndPoints;

public static class AccountEndpoints
{
    public static async Task<IResult> ChangePassword(
        PasswordChangeRequest request,
        ClaimsPrincipal principal,
        AppDbContext db,
        ITokenService tokenService,
        IAuditService audit,
        HttpContext httpContext)
    {
        var userId = DeviceAuthHelper.GetUserId(principal);
        var deviceId = DeviceAuthHelper.GetDeviceId(principal);

        // Verify caller's device is approved
        var callerDevice = await db.Devices.FirstOrDefaultAsync(d =>
            d.Id == deviceId && d.UserId == userId && d.Status == DeviceStatus.Approved);
        if (callerDevice is null)
            return Results.Forbid();

        var user = await db.Users.FirstOrDefaultAsync(u => u.Id == userId);
        if (user is null)
            return Results.Unauthorized();

        // Step-up: verify current password via LoginSession proof
        var session = await db.LoginSessions.FirstOrDefaultAsync(s =>
            s.Id == request.CurrentProof.LoginSessionId && !s.IsCompleted && s.ExpiresAt > DateTime.UtcNow);

        if (session is null)
            return Results.Unauthorized();

        var clientProofBytes = Convert.FromBase64String(request.CurrentProof.ClientProof);
        if (!PasswordVerifier.VerifyClientProof(user.PasswordVerifier, session.Nonce, session.Id, clientProofBytes))
            return Results.Unauthorized();

        session.IsCompleted = true;

        await using var transaction = await db.Database.BeginTransactionAsync();

        user.PasswordVerifier = Convert.FromBase64String(request.NewVerifier.Verifier);
        user.PasswordKdfConfig = System.Text.Json.JsonSerializer.Serialize(request.NewVerifier.Kdf);
        user.UpdatedAt = DateTime.UtcNow;

        var oldEnvelope = await db.VaultKeyEnvelopes.FirstOrDefaultAsync(e =>
            e.UserId == userId && e.EnvelopeType == EnvelopeType.Password && e.RevokedAt == null);
        oldEnvelope?.RevokedAt = DateTime.UtcNow;

        db.VaultKeyEnvelopes.Add(new VaultKeyEnvelope
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            EnvelopeType = EnvelopeType.Password,
            WrappedKeyPayload = EnvelopeHelper.ToBytes(request.NewPasswordEnvelope),
            CreatedAt = DateTime.UtcNow,
        });

        audit.LogEvent(AuditEvents.PasswordChanged, userId, deviceId,
            ipAddress: httpContext.Connection.RemoteIpAddress?.ToString());

        await tokenService.RevokeAllUserTokensAsync(userId);

        var email = principal.FindFirstValue(ClaimTypes.Email) ?? user.Email;
        var accessToken = tokenService.GenerateAccessToken(userId, email, deviceId);
        var (refreshToken, _) = await tokenService.GenerateRefreshTokenAsync(userId, deviceId);

        // Single save: password change + revocation + new token + audit
        await db.SaveChangesAsync();
        await transaction.CommitAsync();

        var isWeb = LoginHelper.IsWebClient(callerDevice.ClientType);
        if (isWeb)
            LoginHelper.SetTokenCookies(httpContext, accessToken, refreshToken);

        return Results.Ok(new PasswordChangeResponse(
            isWeb ? null : accessToken,
            isWeb ? null : refreshToken));
    }

    public static async Task<IResult> LogVaultExported(
        ClaimsPrincipal principal,
        AppDbContext db,
        IAuditService audit,
        HttpContext httpContext)
    {
        var userId = DeviceAuthHelper.GetUserId(principal);
        var deviceId = DeviceAuthHelper.GetDeviceId(principal);
        audit.LogEvent(AuditEvents.VaultExported, userId, deviceId,
            ipAddress: httpContext.Connection.RemoteIpAddress?.ToString());
        await db.SaveChangesAsync();
        return Results.Ok();
    }

    public static async Task<IResult> LogVaultImported(
        ClaimsPrincipal principal,
        AppDbContext db,
        IAuditService audit,
        HttpContext httpContext)
    {
        var userId = DeviceAuthHelper.GetUserId(principal);
        var deviceId = DeviceAuthHelper.GetDeviceId(principal);
        audit.LogEvent(AuditEvents.VaultImported, userId, deviceId,
            ipAddress: httpContext.Connection.RemoteIpAddress?.ToString());
        await db.SaveChangesAsync();
        return Results.Ok();
    }
}
