using Microsoft.EntityFrameworkCore;
using PsTotp.Server.Application.Crypto;
using PsTotp.Server.Application.DTOs;
using PsTotp.Server.Application.Services;
using PsTotp.Server.Domain.Entities;
using PsTotp.Server.Infrastructure.Data;

namespace PsTotp.Server.Api.EndPoints;

/// <summary>
/// Public recovery flow: redeem code → get material → complete.
/// </summary>
public static class RecoveryFlowEndpoints
{
    public static async Task<IResult> RedeemCode(
        RecoveryRedeemRequest request,
        AppDbContext db,
        IConfiguration configuration,
        IRateLimiter rateLimiter,
        IAuditService audit,
        HttpContext httpContext)
    {
        if (rateLimiter.IsRateLimited(request.Email, Application.SharedConstants.RateLimitRecovery))
            return Results.StatusCode(429);

        var user = await db.Users.FirstOrDefaultAsync(u => u.Email == request.Email);
        if (user is null)
            return Results.Unauthorized();

        var session = await db.LoginSessions.FirstOrDefaultAsync(s =>
            s.Id == request.VerifierProof.LoginSessionId && !s.IsCompleted && s.ExpiresAt > DateTime.UtcNow);
        if (session is null)
            return Results.Unauthorized();

        var proofBytes = Convert.FromBase64String(request.VerifierProof.ClientProof);
        if (!PasswordVerifier.VerifyClientProof(user.PasswordVerifier, session.Nonce, session.Id, proofBytes))
            return Results.Unauthorized();

        session.IsCompleted = true;

        // Serializable transaction prevents concurrent creation of multiple active sessions
        await using var transaction = await db.Database.BeginTransactionAsync(System.Data.IsolationLevel.Serializable);

        var hasActiveSession = await db.RecoverySessions.AnyAsync(s =>
            s.UserId == user.Id
            && (s.Status == RecoverySessionStatus.Pending || s.Status == RecoverySessionStatus.Ready)
            && s.ExpiresAt > DateTime.UtcNow);
        if (hasActiveSession)
            return Results.Conflict(new { Error = "An active recovery session already exists" });

        // Use dedicated recovery code salt if available, fall back to KDF salt for legacy accounts
        byte[] salt;
        if (!string.IsNullOrEmpty(user.RecoveryCodeSalt))
            salt = Convert.FromBase64String(user.RecoveryCodeSalt);
        else
        {
            var kdfConfig = System.Text.Json.JsonSerializer.Deserialize<KdfConfigDto>(user.PasswordKdfConfig)!;
            salt = Convert.FromBase64String(kdfConfig.Salt);
        }

        var unusedCodes = await db.RecoveryCodes.Where(c =>
            c.UserId == user.Id && c.UsedAt == null && c.ReplacedAt == null).ToListAsync();

        RecoveryCode? matchingCode = null;
        foreach (var code in unusedCodes)
        {
            var expectedHash = Convert.FromBase64String(code.CodeHash);
            if (Argon2Kdf.VerifyRecoveryCode(request.RecoveryCode, salt, expectedHash))
            {
                matchingCode = code;
                break;
            }
        }

        if (matchingCode is null)
        {
            rateLimiter.RecordAttempt(request.Email, Application.SharedConstants.RateLimitRecovery);
            audit.LogEvent(AuditEvents.RecoveryCodeFailed, user.Id,
                ipAddress: httpContext.Connection.RemoteIpAddress?.ToString());
            await db.SaveChangesAsync();
            return Results.BadRequest(new { Error = "Invalid recovery code" });
        }

        matchingCode.UsedAt = DateTime.UtcNow;

        var holdHours = configuration.GetValue("Recovery:HoldPeriodHours", 24);
        var recoverySession = new RecoverySession
        {
            Id = Guid.NewGuid(),
            UserId = user.Id,
            Status = RecoverySessionStatus.Pending,
            RequiresWebAuthn = await db.WebAuthnCredentials.AnyAsync(c =>
                c.UserId == user.Id && c.RevokedAt == null),
            WebAuthnCompleted = false,
            CreatedAt = DateTime.UtcNow,
            ReleaseEarliestAt = DateTime.UtcNow.AddHours(holdHours),
            ExpiresAt = DateTime.UtcNow.AddHours(72),
        };

        db.RecoverySessions.Add(recoverySession);
        await db.SaveChangesAsync();
        await transaction.CommitAsync();

        audit.LogEvent(AuditEvents.RecoveryCodeRedeemed, user.Id,
            eventData: new { RecoverySessionId = recoverySession.Id, matchingCode.CodeSlot },
            ipAddress: httpContext.Connection.RemoteIpAddress?.ToString());

        return Results.Ok(new RecoveryRedeemResponse(
            recoverySession.Id,
            recoverySession.RequiresWebAuthn,
            recoverySession.ReleaseEarliestAt));
    }

    public static async Task<IResult> GetMaterial(
        Guid sessionId,
        RecoveryMaterialRequest request,
        AppDbContext db,
        IAuditService audit,
        HttpContext httpContext)
    {
        var session = await db.RecoverySessions.FirstOrDefaultAsync(s =>
            s.Id == sessionId
            && s.Status != RecoverySessionStatus.Completed
            && s.Status != RecoverySessionStatus.Cancelled
            && s.ExpiresAt > DateTime.UtcNow);

        if (session is null)
            return Results.NotFound();

        if (session.RequiresWebAuthn && !session.WebAuthnCompleted)
            return Results.Ok(new RecoveryMaterialResponse("webauthn_required", null, null, null));

        if (DateTime.UtcNow < session.ReleaseEarliestAt)
            return Results.Ok(new RecoveryMaterialResponse("pending", null, null, session.ReleaseEarliestAt));

        // Idempotent: reuse existing replacement device if already created (repeated polling)
        Device? replacementDevice = null;
        if (session.ReplacementDeviceId.HasValue)
        {
            replacementDevice = await db.Devices.FirstOrDefaultAsync(d =>
                d.Id == session.ReplacementDeviceId.Value);
        }

        if (replacementDevice is null)
        {
            replacementDevice = new Device
            {
                Id = Guid.NewGuid(),
                UserId = session.UserId,
                DeviceName = request.ReplacementDevice.DeviceName,
                Platform = request.ReplacementDevice.Platform,
                ClientType = request.ReplacementDevice.ClientType,
                DevicePublicKey = request.ReplacementDevice.DevicePublicKey,
                Status = DeviceStatus.Approved,
                CreatedAt = DateTime.UtcNow,
                ApprovedAt = DateTime.UtcNow,
            };
            db.Devices.Add(replacementDevice);
            session.ReplacementDeviceId = replacementDevice.Id;
        }

        session.Status = RecoverySessionStatus.Ready;

        var recoveryEnvelope = await db.VaultKeyEnvelopes.FirstOrDefaultAsync(e =>
            e.UserId == session.UserId && e.EnvelopeType == EnvelopeType.Recovery && e.RevokedAt == null);

        audit.LogEvent(AuditEvents.RecoveryMaterialReleased, session.UserId, replacementDevice.Id,
            eventData: new { RecoverySessionId = session.Id },
            ipAddress: httpContext.Connection.RemoteIpAddress?.ToString());

        await db.SaveChangesAsync();

        EnvelopeDto? envelopeDto = recoveryEnvelope != null
            ? EnvelopeHelper.FromBytes(recoveryEnvelope.WrappedKeyPayload) : null;

        return Results.Ok(new RecoveryMaterialResponse("ready", envelopeDto, replacementDevice.Id, null));
    }

    public static async Task<IResult> Complete(
        Guid sessionId,
        RecoveryCompleteRequest request,
        AppDbContext db,
        ITokenService tokenService,
        IAuditService audit,
        HttpContext httpContext)
    {
        var session = await db.RecoverySessions.FirstOrDefaultAsync(s =>
            s.Id == sessionId && s.Status == RecoverySessionStatus.Ready);

        if (session is null)
            return Results.NotFound();

        // Use server-stored device ID, not client-supplied value
        var replacementDeviceId = session.ReplacementDeviceId
            ?? throw new InvalidOperationException("Recovery session has no replacement device");

        await using var transaction = await db.Database.BeginTransactionAsync();

        db.VaultKeyEnvelopes.Add(new VaultKeyEnvelope
        {
            Id = Guid.NewGuid(),
            UserId = session.UserId,
            DeviceId = replacementDeviceId,
            EnvelopeType = EnvelopeType.Device,
            WrappedKeyPayload = EnvelopeHelper.ToBytes(request.DeviceEnvelope),
            CreatedAt = DateTime.UtcNow,
        });

        var oldCodes = await db.RecoveryCodes
            .Where(c => c.UserId == session.UserId && c.ReplacedAt == null)
            .ToListAsync();
        foreach (var code in oldCodes)
            code.ReplacedAt = DateTime.UtcNow;

        for (var i = 0; i < request.RotatedRecovery.RecoveryCodeHashes.Count; i++)
        {
            db.RecoveryCodes.Add(new RecoveryCode
            {
                Id = Guid.NewGuid(),
                UserId = session.UserId,
                CodeHash = request.RotatedRecovery.RecoveryCodeHashes[i],
                CodeSlot = i,
                CreatedAt = DateTime.UtcNow,
            });
        }

        // Update the recovery code salt
        if (request.RotatedRecovery.RecoveryCodeSalt != null)
        {
            var recoveryUser = await db.Users.FindAsync(session.UserId);
            if (recoveryUser != null)
                recoveryUser.RecoveryCodeSalt = request.RotatedRecovery.RecoveryCodeSalt;
        }

        var oldRecoveryEnvelope = await db.VaultKeyEnvelopes.FirstOrDefaultAsync(e =>
            e.UserId == session.UserId && e.EnvelopeType == EnvelopeType.Recovery && e.RevokedAt == null);
        if (oldRecoveryEnvelope != null)
            oldRecoveryEnvelope.RevokedAt = DateTime.UtcNow;

        db.VaultKeyEnvelopes.Add(new VaultKeyEnvelope
        {
            Id = Guid.NewGuid(),
            UserId = session.UserId,
            EnvelopeType = EnvelopeType.Recovery,
            WrappedKeyPayload = EnvelopeHelper.ToBytes(new EnvelopeDto(
                request.RotatedRecovery.RecoveryEnvelopeCiphertext,
                request.RotatedRecovery.RecoveryEnvelopeNonce,
                request.RotatedRecovery.RecoveryEnvelopeVersion)),
            CreatedAt = DateTime.UtcNow,
        });

        session.Status = RecoverySessionStatus.Completed;
        session.CompletedAt = DateTime.UtcNow;

        audit.LogEvent(AuditEvents.RecoveryCompleted, session.UserId, replacementDeviceId,
            eventData: new { RecoverySessionId = session.Id },
            ipAddress: httpContext.Connection.RemoteIpAddress?.ToString());

        // Issue auth tokens within the same transaction so recovery + tokens are atomic
        var user = await db.Users.FirstOrDefaultAsync(u => u.Id == session.UserId);
        var device = await db.Devices.FirstOrDefaultAsync(d => d.Id == replacementDeviceId);

        string? accessToken = null;
        string? refreshToken = null;
        if (user != null && device != null)
        {
            accessToken = tokenService.GenerateAccessToken(user.Id, user.Email, device.Id);
            (refreshToken, _) = await tokenService.GenerateRefreshTokenAsync(user.Id, device.Id);
        }

        await db.SaveChangesAsync();
        await transaction.CommitAsync();

        // Set cookies after commit so a rollback doesn't leave invalid cookies
        if (user != null && device != null && accessToken != null)
        {
            var isWeb = LoginHelper.IsWebClient(device.ClientType);
            if (isWeb)
                LoginHelper.SetTokenCookies(httpContext, accessToken, refreshToken!);

            return Results.Ok(new { userId = session.UserId, accessToken = isWeb ? null : accessToken, refreshToken = isWeb ? null : refreshToken });
        }

        return Results.Ok(new { userId = session.UserId, accessToken = (string?)null, refreshToken = (string?)null });
    }
}
