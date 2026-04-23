using System.Security.Claims;
using System.Text.Json;
using Fido2NetLib;
using Fido2NetLib.Objects;
using Microsoft.EntityFrameworkCore;
using PsTotp.Server.Application.DTOs;
using PsTotp.Server.Application.Services;
using PsTotp.Server.Domain.Entities;
using PsTotp.Server.Infrastructure.Data;

namespace PsTotp.Server.Api.EndPoints;

public static partial class WebAuthnRegistrationEndpoints
{
    [LoggerMessage(Level = LogLevel.Warning, Message = "WebAuthn registration verification failed")]
    private static partial void LogRegistrationFailed(ILogger logger, Exception ex);

    private static readonly TimeSpan CeremonyExpiry = TimeSpan.FromMinutes(5);

    public static async Task<IResult> Begin(
        ClaimsPrincipal principal,
        AppDbContext db,
        IFido2 fido2)
    {
        var userId = DeviceAuthHelper.GetUserId(principal);
        var callerDevice = await DeviceAuthHelper.GetApprovedCallerDevice(principal, db);
        if (callerDevice is null)
            return Results.Forbid();

        var user = await db.Users.FirstOrDefaultAsync(u => u.Id == userId);
        if (user is null)
            return Results.Unauthorized();

        var existingCreds = await db.WebAuthnCredentials
            .Where(c => c.UserId == userId && c.RevokedAt == null)
            .Select(c => new { c.CredentialId })
            .ToListAsync();
        var existingCredentials = existingCreds
            .Select(c => new PublicKeyCredentialDescriptor(PublicKeyCredentialType.PublicKey, c.CredentialId))
            .ToList();

        var fido2User = new Fido2User
        {
            Id = userId.ToByteArray(),
            Name = user.Email,
            DisplayName = user.Email,
        };

        var options = fido2.RequestNewCredential(new RequestNewCredentialParams
        {
            User = fido2User,
            ExcludeCredentials = existingCredentials,
            AuthenticatorSelection = new AuthenticatorSelection
            {
                ResidentKey = ResidentKeyRequirement.Preferred,
                UserVerification = UserVerificationRequirement.Preferred,
            },
            AttestationPreference = AttestationConveyancePreference.None,
        });

        var ceremony = new WebAuthnCeremony
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            CeremonyType = WebAuthnCeremonyType.Register,
            OptionsJson = options.ToJson(),
            CreatedAt = DateTime.UtcNow,
            ExpiresAt = DateTime.UtcNow.Add(CeremonyExpiry),
        };
        db.WebAuthnCeremonies.Add(ceremony);
        await db.SaveChangesAsync();

        var optionsJson = JsonSerializer.Deserialize<JsonElement>(options.ToJson());
        return Results.Ok(new WebAuthnRegisterBeginResponse(ceremony.Id, optionsJson));
    }

    public static async Task<IResult> Complete(
        WebAuthnRegisterCompleteRequest request,
        ClaimsPrincipal principal,
        AppDbContext db,
        IFido2 fido2,
        IAuditService audit,
        ILoggerFactory loggerFactory,
        HttpContext httpContext)
    {
        var userId = DeviceAuthHelper.GetUserId(principal);
        var callerDevice = await DeviceAuthHelper.GetApprovedCallerDevice(principal, db);
        if (callerDevice is null)
            return Results.Forbid();

        var ceremony = await db.WebAuthnCeremonies.FirstOrDefaultAsync(c =>
            c.Id == request.CeremonyId && c.UserId == userId
            && c.CeremonyType == WebAuthnCeremonyType.Register && !c.IsCompleted && c.ExpiresAt > DateTime.UtcNow);
        if (ceremony is null)
            return Results.BadRequest(new { Error = "Invalid or expired ceremony" });

        var options = CredentialCreateOptions.FromJson(ceremony.OptionsJson);
        var attestationResponse = JsonSerializer.Deserialize<AuthenticatorAttestationRawResponse>(
            request.AttestationResponse.GetRawText())!;

        RegisteredPublicKeyCredential credential;
        try
        {
            credential = await fido2.MakeNewCredentialAsync(new MakeNewCredentialParams
            {
                AttestationResponse = attestationResponse,
                OriginalOptions = options,
                IsCredentialIdUniqueToUserCallback = async (args, ct) =>
                {
                    var exists = await db.WebAuthnCredentials.AnyAsync(
                        c => c.CredentialId == args.CredentialId, ct);
                    return !exists;
                },
            });
        }
        catch (Fido2VerificationException ex)
        {
            LogRegistrationFailed(loggerFactory.CreateLogger<IFido2>(), ex);
            return Results.BadRequest(new { Error = "Passkey registration failed" });
        }

        var webAuthnCred = new WebAuthnCredential
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            CredentialId = credential.Id,
            PublicKey = credential.PublicKey,
            SignCount = credential.SignCount,
            FriendlyName = string.IsNullOrWhiteSpace(request.FriendlyName) ? "Passkey" : request.FriendlyName.Trim(),
            Transports = credential.Transports != null ? JsonSerializer.Serialize(credential.Transports) : null,
            CreatedAt = DateTime.UtcNow,
        };
        db.WebAuthnCredentials.Add(webAuthnCred);

        ceremony.IsCompleted = true;

        audit.LogEvent(AuditEvents.WebAuthnCredentialRegistered, userId, callerDevice.Id,
            eventData: new { CredentialId = webAuthnCred.Id, webAuthnCred.FriendlyName },
            ipAddress: httpContext.Connection.RemoteIpAddress?.ToString());

        await db.SaveChangesAsync();
        return Results.Ok(new { webAuthnCred.Id, webAuthnCred.FriendlyName });
    }
}
