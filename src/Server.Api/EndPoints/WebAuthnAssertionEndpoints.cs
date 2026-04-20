using System.Buffers.Text;
using System.Text.Json;
using Fido2NetLib;
using Fido2NetLib.Objects;
using Microsoft.EntityFrameworkCore;
using PsTotp.Server.Application.DTOs;
using PsTotp.Server.Application.Services;
using PsTotp.Server.Domain.Entities;
using PsTotp.Server.Infrastructure.Data;

namespace PsTotp.Server.Api.EndPoints;

public static class WebAuthnAssertionEndpoints
{
    private static readonly TimeSpan CeremonyExpiry = TimeSpan.FromMinutes(5);

    public static async Task<IResult> Begin(
        WebAuthnAssertBeginRequest request,
        AppDbContext db,
        IFido2 fido2)
    {
        Guid? userId = null;

        if (!string.IsNullOrEmpty(request.Email))
        {
            var user = await db.Users.FirstOrDefaultAsync(u => u.Email == request.Email);
            if (user != null)
                userId = user.Id;
        }
        else if (request.RecoverySessionId.HasValue)
        {
            var session = await db.RecoverySessions.FirstOrDefaultAsync(s =>
                s.Id == request.RecoverySessionId.Value
                && s.RequiresWebAuthn && !s.WebAuthnCompleted
                && s.Status != RecoverySessionStatus.Completed
                && s.Status != RecoverySessionStatus.Cancelled
                && s.ExpiresAt > DateTime.UtcNow);
            if (session is null)
                return Results.BadRequest(new { Error = "Invalid recovery session" });
            userId = session.UserId;
        }
        else
        {
            return Results.BadRequest(new { Error = "Passkey authentication is not available" });
        }

        var credentials = userId.HasValue
            ? await db.WebAuthnCredentials
                .Where(c => c.UserId == userId.Value && c.RevokedAt == null)
                .ToListAsync()
            : [];

        if (!userId.HasValue || credentials.Count == 0)
            return Results.BadRequest(new { Error = "Passkey authentication is not available" });

        var allowedCredentials = credentials.Select(c =>
        {
            var transports = c.Transports != null
                ? JsonSerializer.Deserialize<AuthenticatorTransport[]>(c.Transports)
                : null;
            return new PublicKeyCredentialDescriptor(PublicKeyCredentialType.PublicKey, c.CredentialId, transports);
        }).ToList();

        var options = fido2.GetAssertionOptions(new GetAssertionOptionsParams
        {
            AllowedCredentials = allowedCredentials,
            UserVerification = UserVerificationRequirement.Preferred,
        });

        var ceremony = new WebAuthnCeremony
        {
            Id = Guid.NewGuid(),
            UserId = userId.Value,
            CeremonyType = WebAuthnCeremonyType.Assert,
            OptionsJson = options.ToJson(),
            RecoverySessionId = request.RecoverySessionId,
            CreatedAt = DateTime.UtcNow,
            ExpiresAt = DateTime.UtcNow.Add(CeremonyExpiry),
        };
        db.WebAuthnCeremonies.Add(ceremony);
        await db.SaveChangesAsync();

        var optionsJson = JsonSerializer.Deserialize<JsonElement>(options.ToJson());
        return Results.Ok(new WebAuthnAssertBeginResponse(ceremony.Id, optionsJson));
    }

    public static async Task<IResult> Complete(
        WebAuthnAssertCompleteRequest request,
        AppDbContext db,
        IFido2 fido2,
        ITokenService tokenService,
        IAuditService audit,
        IConfiguration configuration,
        ILoggerFactory loggerFactory,
        HttpContext httpContext)
    {
        var ceremony = await db.WebAuthnCeremonies.FirstOrDefaultAsync(c =>
            c.Id == request.CeremonyId && c.CeremonyType == WebAuthnCeremonyType.Assert
            && !c.IsCompleted && c.ExpiresAt > DateTime.UtcNow);
        if (ceremony is null)
            return Results.BadRequest(new { Error = "Invalid or expired ceremony" });

        var options = AssertionOptions.FromJson(ceremony.OptionsJson);
        var assertionResponse = JsonSerializer.Deserialize<AuthenticatorAssertionRawResponse>(
            request.AssertionResponse.GetRawText())!;

        var credentialIdBytes = Base64Url.DecodeFromChars(assertionResponse.Id);
        var allUserCreds = await db.WebAuthnCredentials
            .Where(c => c.UserId == ceremony.UserId && c.RevokedAt == null)
            .ToListAsync();
        var storedCredential = allUserCreds.FirstOrDefault(c => c.CredentialId.AsSpan().SequenceEqual(credentialIdBytes));
        if (storedCredential is null)
            return Results.BadRequest(new { Error = "Passkey verification failed" });

        VerifyAssertionResult assertionResult;
        try
        {
            assertionResult = await fido2.MakeAssertionAsync(new MakeAssertionParams
            {
                AssertionResponse = assertionResponse,
                OriginalOptions = options,
                StoredPublicKey = storedCredential.PublicKey,
                StoredSignatureCounter = (uint)(storedCredential.SignCount ?? 0),
                IsUserHandleOwnerOfCredentialIdCallback = (args, _) =>
                {
                    var userIdBytes = ceremony.UserId.ToByteArray();
                    return Task.FromResult(args.UserHandle.AsSpan().SequenceEqual(userIdBytes));
                },
            });
        }
        catch (Fido2VerificationException ex)
        {
            loggerFactory.CreateLogger<IFido2>().LogWarning(ex, "WebAuthn assertion verification failed");
            return Results.BadRequest(new { Error = "Passkey verification failed" });
        }

        storedCredential.SignCount = assertionResult.SignCount;
        storedCredential.LastUsedAt = DateTime.UtcNow;
        ceremony.IsCompleted = true;

        // Recovery step-up flow
        if (ceremony.RecoverySessionId.HasValue)
        {
            // Re-verify the recovery session is still in a valid state. It may
            // have been cancelled, expired, or already completed between begin
            // and complete. Mirror the predicate used by Begin() above.
            var recoverySession = await db.RecoverySessions.FirstOrDefaultAsync(s =>
                s.Id == ceremony.RecoverySessionId.Value
                && s.UserId == ceremony.UserId
                && s.RequiresWebAuthn
                && !s.WebAuthnCompleted
                && s.Status != RecoverySessionStatus.Completed
                && s.Status != RecoverySessionStatus.Cancelled
                && s.ExpiresAt > DateTime.UtcNow);

            if (recoverySession is null)
            {
                // Persist the ceremony completion + sign count even though the
                // recovery flow has ended, to prevent replay of this assertion.
                await db.SaveChangesAsync();
                return Results.BadRequest(new { Error = "Recovery session is no longer valid" });
            }

            recoverySession.WebAuthnCompleted = true;

            audit.LogEvent(AuditEvents.WebAuthnAssertionVerified, ceremony.UserId,
                eventData: new { Flow = "recovery_step_up", ceremony.RecoverySessionId },
                ipAddress: httpContext.Connection.RemoteIpAddress?.ToString());

            await db.SaveChangesAsync();
            return Results.Ok(new { Success = true });
        }

        // Login flow
        var user = await db.Users.FirstOrDefaultAsync(u => u.Id == ceremony.UserId);
        if (user is null)
            return Results.Unauthorized();

        if (user.DisabledAt.HasValue)
            return Results.Json(new { Error = AuthConstants.ErrorAccountDisabled }, statusCode: 403);

        // Sync role from config
        var adminEmails = configuration.GetSection("Admins").Get<string[]>() ?? [];
        var shouldBeAdmin = adminEmails.Contains(user.Email, StringComparer.OrdinalIgnoreCase);
        user.Role = shouldBeAdmin ? UserRole.Admin : UserRole.User;

        if (request.Device is null)
            return Results.BadRequest(new { Error = "Device information required for login" });

        var device = await LoginHelper.MatchOrCreateDevice(db, user.Id, request.Device);
        device!.LastSeenAt = DateTime.UtcNow;
        user.LastLoginAt = DateTime.UtcNow;

        var roleStr = user.Role == UserRole.Admin ? Application.SharedConstants.AdminRole : null;
        var accessToken = tokenService.GenerateAccessToken(user.Id, user.Email, device.Id, roleStr);
        var (refreshToken, _) = await tokenService.GenerateRefreshTokenAsync(user.Id, device.Id);

        audit.LogEvent(AuditEvents.LoginSuccess, user.Id, device.Id,
            eventData: new { device.DeviceName, Method = "webauthn" },
            ipAddress: httpContext.Connection.RemoteIpAddress?.ToString());

        LoginEnvelopes? envelopes = null;
        Guid? approvalRequestId = null;

        if (device.Status == DeviceStatus.Approved)
            envelopes = await LoginHelper.GetLoginEnvelopes(db, user.Id, device);
        else
            approvalRequestId = device.Id;

        await db.SaveChangesAsync();

        return Results.Ok(LoginHelper.BuildLoginResponse(
            httpContext, user.Id, device, accessToken, refreshToken, envelopes, approvalRequestId,
            roleStr, user.ForcePasswordReset));
    }
}
