using System.Globalization;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using PsTotp.Server.Application.DTOs;
using PsTotp.Server.Application.Services;
using PsTotp.Server.Domain.Entities;
using PsTotp.Server.Infrastructure.Data;

namespace PsTotp.Server.Api.EndPoints;

public static class PasswordResetEndpoints
{
    private const int MaxResetSessionsPerEmail = 3;

    public static async Task<IResult> BeginPasswordReset(
        BeginPasswordResetRequest request,
        AppDbContext db,
        IEmailService emailService,
        IAuditService audit,
        HttpContext httpContext)
    {
        // Rate limit: max active sessions per email to prevent brute-force across sessions
        var recentCutoff = DateTime.UtcNow.AddMinutes(-15);
        var activeSessions = await db.PasswordResetSessions.CountAsync(s =>
            s.Email == request.Email && !s.IsCompleted && s.CreatedAt > recentCutoff);
        if (activeSessions >= MaxResetSessionsPerEmail)
            return Results.StatusCode(429);

        var code = RandomNumberGenerator.GetInt32(100000, 999999).ToString(CultureInfo.InvariantCulture);

        var session = new PasswordResetSession
        {
            Id = Guid.NewGuid(),
            Email = request.Email,
            VerificationCode = code,
            IsVerified = false,
            CreatedAt = DateTime.UtcNow,
            ExpiresAt = DateTime.UtcNow.AddMinutes(15),
        };

        // Match device if provided (for device envelope on verify)
        var user = await db.Users.FirstOrDefaultAsync(u => u.Email == request.Email);
        if (user != null && request.Device != null && !string.IsNullOrEmpty(request.Device.DevicePublicKey))
        {
            var device = await db.Devices.FirstOrDefaultAsync(d =>
                d.UserId == user.Id && d.DevicePublicKey == request.Device.DevicePublicKey
                && d.Status == DeviceStatus.Approved);
            session.DeviceId = device?.Id;
        }

        db.PasswordResetSessions.Add(session);

        if (user != null)
        {
            audit.LogEvent(AuditEvents.PasswordResetRequested, user.Id,
                ipAddress: httpContext.Connection.RemoteIpAddress?.ToString());
        }

        await db.SaveChangesAsync();

        // Send code or return inline — enumeration resistant (always returns success shape)
        string? returnCode = null;
        if (emailService.IsConfigured)
        {
            try
            {
                await emailService.SendVerificationCodeAsync(request.Email, code);
            }
            catch
            {
                return Results.StatusCode(502);
            }
        }
        else
        {
            returnCode = code;
        }

        return Results.Ok(new BeginPasswordResetResponse(session.Id, emailService.IsConfigured, returnCode));
    }

    public static async Task<IResult> VerifyPasswordResetCode(
        VerifyPasswordResetCodeRequest request,
        AppDbContext db)
    {
        var session = await db.PasswordResetSessions.FirstOrDefaultAsync(s =>
            s.Id == request.ResetSessionId && !s.IsCompleted && s.ExpiresAt > DateTime.UtcNow);

        if (session is null)
            return Results.BadRequest(new { Error = "Invalid or expired reset session" });

        // Rate limit: lock after 5 failed attempts
        if (session.FailedVerifyAttempts >= 5)
            return Results.StatusCode(429);

        if (session.VerificationCode != request.VerificationCode)
        {
            session.FailedVerifyAttempts++;
            await db.SaveChangesAsync();
            return Results.BadRequest(new { Error = "Invalid verification code" });
        }

        session.IsVerified = true;
        await db.SaveChangesAsync();

        // Return KDF config and device envelope if available
        var user = await db.Users.FirstOrDefaultAsync(u => u.Email == session.Email);
        if (user is null)
            return Results.Ok(new VerifyPasswordResetCodeResponse(true, null, null));

        var kdfConfig = JsonSerializer.Deserialize<KdfConfigDto>(user.PasswordKdfConfig)!;

        EnvelopeDto? deviceEnvelope = null;
        if (session.DeviceId.HasValue)
        {
            var envelope = await db.VaultKeyEnvelopes.FirstOrDefaultAsync(e =>
                e.UserId == user.Id && e.DeviceId == session.DeviceId
                && e.EnvelopeType == EnvelopeType.Device && e.RevokedAt == null);
            if (envelope != null)
                deviceEnvelope = EnvelopeHelper.FromBytes(envelope.WrappedKeyPayload);
        }

        return Results.Ok(new VerifyPasswordResetCodeResponse(true, kdfConfig, deviceEnvelope));
    }

    public static async Task<IResult> CompletePasswordReset(
        CompletePasswordResetRequest request,
        AppDbContext db,
        ITokenService tokenService,
        IAuditService audit,
        HttpContext httpContext)
    {
        var session = await db.PasswordResetSessions.FirstOrDefaultAsync(s =>
            s.Id == request.ResetSessionId && s.IsVerified && !s.IsCompleted && s.ExpiresAt > DateTime.UtcNow);

        if (session is null)
            return Results.BadRequest(new { Error = "Invalid or expired reset session" });

        var user = await db.Users.FirstOrDefaultAsync(u => u.Email == session.Email);
        if (user is null)
            return Results.BadRequest(new { Error = "Account not found" });

        await using var transaction = await db.Database.BeginTransactionAsync();

        user.PasswordVerifier = Convert.FromBase64String(request.NewVerifier.Verifier);
        user.PasswordKdfConfig = JsonSerializer.Serialize(request.NewVerifier.Kdf);

        var oldEnvelope = await db.VaultKeyEnvelopes.FirstOrDefaultAsync(e =>
            e.UserId == user.Id && e.EnvelopeType == EnvelopeType.Password && e.RevokedAt == null);
        oldEnvelope?.RevokedAt = DateTime.UtcNow;

        db.VaultKeyEnvelopes.Add(new VaultKeyEnvelope
        {
            Id = Guid.NewGuid(),
            UserId = user.Id,
            EnvelopeType = EnvelopeType.Password,
            WrappedKeyPayload = EnvelopeHelper.ToBytes(request.NewPasswordEnvelope),
            CreatedAt = DateTime.UtcNow,
        });

        session.IsCompleted = true;

        await tokenService.RevokeAllUserTokensAsync(user.Id);

        Device? device = null;
        if (session.DeviceId.HasValue)
            device = await db.Devices.FirstOrDefaultAsync(d =>
                d.Id == session.DeviceId.Value && d.Status == DeviceStatus.Approved);

        device ??= await db.Devices.FirstOrDefaultAsync(d =>
            d.UserId == user.Id && d.Status == DeviceStatus.Approved);

        if (device is null)
            return Results.BadRequest(new { Error = "No approved device found" });

        var accessToken = tokenService.GenerateAccessToken(user.Id, user.Email, device.Id);
        var (refreshToken, _) = await tokenService.GenerateRefreshTokenAsync(user.Id, device.Id);

        audit.LogEvent(AuditEvents.PasswordResetCompleted, user.Id, device.Id,
            ipAddress: httpContext.Connection.RemoteIpAddress?.ToString());

        await db.SaveChangesAsync();
        await transaction.CommitAsync();

        return Results.Ok(LoginHelper.BuildLoginResponse(
            httpContext, user.Id, device, accessToken, refreshToken, null, null));
    }
}
