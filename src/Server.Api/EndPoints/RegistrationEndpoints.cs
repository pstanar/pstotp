using System.Globalization;
using System.Security.Cryptography;
using Microsoft.EntityFrameworkCore;
using PsTotp.Server.Application.DTOs;
using PsTotp.Server.Application.Services;
using PsTotp.Server.Domain.Entities;
using PsTotp.Server.Infrastructure.Data;

namespace PsTotp.Server.Api.EndPoints;

public static class RegistrationEndpoints
{
    private const int MaxRegistrationSessionsPerEmail = 3;

    public static async Task<IResult> Begin(
        BeginRegistrationRequest request,
        AppDbContext db,
        IEmailService emailService)
    {
        // Rate limit: max active sessions per email to prevent email spam
        var recentCutoff = DateTime.UtcNow.AddMinutes(-15);
        var activeSessions = await db.RegistrationSessions.CountAsync(s =>
            s.Email == request.Email && s.CreatedAt > recentCutoff);
        if (activeSessions >= MaxRegistrationSessionsPerEmail)
            return Results.StatusCode(429);

        var code = RandomNumberGenerator.GetInt32(100000, 999999).ToString(CultureInfo.InvariantCulture);

        var session = new RegistrationSession
        {
            Id = Guid.NewGuid(),
            Email = request.Email,
            VerificationCode = code,
            IsVerified = false,
            CreatedAt = DateTime.UtcNow,
            ExpiresAt = DateTime.UtcNow.AddMinutes(15),
        };

        db.RegistrationSessions.Add(session);
        await db.SaveChangesAsync();

        string? returnCode = null;
        if (emailService.IsConfigured)
        {
            try
            {
                await emailService.SendVerificationCodeAsync(request.Email, code);
            }
            catch
            {
                // Configured but broken — don't leak code in production
                return Results.StatusCode(502);
            }
        }
        else
        {
            // Not configured — return code inline for zero-config bootstrap
            returnCode = code;
        }

        return Results.Ok(new BeginRegistrationResponse(session.Id, true, returnCode));
    }

    public static async Task<IResult> VerifyEmail(
        VerifyEmailRequest request,
        AppDbContext db)
    {
        var session = await db.RegistrationSessions.FirstOrDefaultAsync(s =>
            s.Id == request.RegistrationSessionId && s.ExpiresAt > DateTime.UtcNow);

        if (session is null)
            return Results.BadRequest(new { Error = "Invalid or expired registration session" });

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

        return Results.Ok(new VerifyEmailResponse(true));
    }

    public static async Task<IResult> Complete(
        RegisterRequest request,
        AppDbContext db,
        ITokenService tokenService,
        IAuditService audit,
        IConfiguration configuration,
        HttpContext httpContext)
    {
        var requireVerification = configuration.GetValue<bool>("Registration:RequireEmailVerification");
        if (requireVerification)
        {
            if (request.RegistrationSessionId is null)
                return Results.BadRequest(new { Error = "Email verification is required" });

            var regSession = await db.RegistrationSessions.FirstOrDefaultAsync(s =>
                s.Id == request.RegistrationSessionId.Value && s.IsVerified && s.ExpiresAt > DateTime.UtcNow);

            if (regSession is null)
                return Results.BadRequest(new { Error = "Invalid or unverified registration session" });

            if (!string.Equals(regSession.Email, request.Email, StringComparison.OrdinalIgnoreCase))
                return Results.BadRequest(new { Error = "Email does not match registration session" });
        }

        if (await db.Users.AnyAsync(u => u.Email == request.Email))
            return Results.Conflict(new { Error = "Email already registered" });

        var userId = Guid.NewGuid();
        var deviceId = Guid.NewGuid();
        var now = DateTime.UtcNow;

        var user = new User
        {
            Id = userId,
            Email = request.Email,
            PasswordVerifier = Convert.FromBase64String(request.PasswordVerifier.Verifier),
            PasswordKdfConfig = System.Text.Json.JsonSerializer.Serialize(request.PasswordVerifier.Kdf),
            RecoveryCodeSalt = request.Recovery.RecoveryCodeSalt,
            CreatedAt = now,
            UpdatedAt = now,
        };

        var device = new Device
        {
            Id = deviceId,
            UserId = userId,
            DeviceName = request.Device.DeviceName,
            Platform = request.Device.Platform,
            ClientType = request.Device.ClientType,
            Status = DeviceStatus.Approved,
            DevicePublicKey = request.Device.DevicePublicKey,
            CreatedAt = now,
            ApprovedAt = now,
        };

        var passwordEnvelope = new VaultKeyEnvelope
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            EnvelopeType = EnvelopeType.Password,
            WrappedKeyPayload = EnvelopeHelper.ToBytes(request.PasswordEnvelope),
            CreatedAt = now,
        };

        var deviceEnvelope = new VaultKeyEnvelope
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            DeviceId = deviceId,
            EnvelopeType = EnvelopeType.Device,
            WrappedKeyPayload = EnvelopeHelper.ToBytes(request.DeviceEnvelope),
            CreatedAt = now,
        };

        var recoveryEnvelope = new VaultKeyEnvelope
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            EnvelopeType = EnvelopeType.Recovery,
            WrappedKeyPayload = EnvelopeHelper.ToBytes(new EnvelopeDto(
                request.Recovery.RecoveryEnvelopeCiphertext,
                request.Recovery.RecoveryEnvelopeNonce,
                request.Recovery.RecoveryEnvelopeVersion)),
            CreatedAt = now,
        };

        db.Users.Add(user);
        db.Devices.Add(device);
        db.VaultKeyEnvelopes.AddRange(passwordEnvelope, deviceEnvelope, recoveryEnvelope);

        for (var i = 0; i < request.Recovery.RecoveryCodeHashes.Count; i++)
        {
            db.RecoveryCodes.Add(new RecoveryCode
            {
                Id = Guid.NewGuid(),
                UserId = userId,
                CodeHash = request.Recovery.RecoveryCodeHashes[i],
                CodeSlot = i,
                CreatedAt = now,
            });
        }

        audit.LogEvent(AuditEvents.AccountCreated, userId, deviceId,
            eventData: new { request.Email, request.Device.DeviceName },
            ipAddress: httpContext.Connection.RemoteIpAddress?.ToString());

        var accessToken = tokenService.GenerateAccessToken(userId, request.Email, deviceId);
        var (refreshToken, _) = await tokenService.GenerateRefreshTokenAsync(userId, deviceId);

        // Single save persists user, device, envelopes, codes, audit, AND refresh token atomically
        await db.SaveChangesAsync();

        var isWeb = LoginHelper.IsWebClient(request.Device.ClientType);
        if (isWeb)
            LoginHelper.SetTokenCookies(httpContext, accessToken, refreshToken);

        return Results.Ok(new RegisterResponse(userId, deviceId, isWeb ? null : accessToken, isWeb ? null : refreshToken));
    }
}
