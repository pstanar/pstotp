using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using PsTotp.Server.Application.DTOs;
using PsTotp.Server.Application.Services;
using PsTotp.Server.Domain.Entities;
using PsTotp.Server.Infrastructure.Data;

namespace PsTotp.Server.Api.EndPoints;

/// <summary>
/// Authenticated recovery management: regenerate codes, cancel sessions.
/// </summary>
public static class RecoveryManagementEndpoints
{
    public static async Task<IResult> RegenerateCodes(
        RecoveryCodeRegenerateRequest request,
        ClaimsPrincipal user,
        AppDbContext db,
        IAuditService audit,
        HttpContext httpContext)
    {
        var userId = DeviceAuthHelper.GetUserId(user);
        var callerDevice = await DeviceAuthHelper.GetApprovedCallerDevice(user, db);
        if (callerDevice is null)
            return Results.Forbid();

        // If code hashes are provided, rotate them; otherwise keep existing codes
        // (envelope-only rotation for password change)
        if (request.RotatedRecovery.RecoveryCodeHashes.Count > 0)
        {
            var oldCodes = await db.RecoveryCodes
                .Where(c => c.UserId == userId && c.ReplacedAt == null)
                .ToListAsync();
            foreach (var code in oldCodes)
                code.ReplacedAt = DateTime.UtcNow;

            for (var i = 0; i < request.RotatedRecovery.RecoveryCodeHashes.Count; i++)
            {
                db.RecoveryCodes.Add(new RecoveryCode
                {
                    Id = Guid.NewGuid(),
                    UserId = userId,
                    CodeHash = request.RotatedRecovery.RecoveryCodeHashes[i],
                    CodeSlot = i,
                    CreatedAt = DateTime.UtcNow,
                });
            }
        }

        var oldEnvelope = await db.VaultKeyEnvelopes.FirstOrDefaultAsync(e =>
            e.UserId == userId && e.EnvelopeType == EnvelopeType.Recovery && e.RevokedAt == null);
        oldEnvelope?.RevokedAt = DateTime.UtcNow;

        db.VaultKeyEnvelopes.Add(new VaultKeyEnvelope
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            EnvelopeType = EnvelopeType.Recovery,
            WrappedKeyPayload = EnvelopeHelper.ToBytes(new EnvelopeDto(
                request.RotatedRecovery.RecoveryEnvelopeCiphertext,
                request.RotatedRecovery.RecoveryEnvelopeNonce,
                request.RotatedRecovery.RecoveryEnvelopeVersion)),
            CreatedAt = DateTime.UtcNow,
        });

        // Update recovery code salt on user (single SaveChangesAsync = single transaction)
        if (request.RotatedRecovery.RecoveryCodeSalt != null)
        {
            var userEntity = await db.Users.FindAsync(userId);
            if (userEntity != null)
                userEntity.RecoveryCodeSalt = request.RotatedRecovery.RecoveryCodeSalt;
        }

        audit.LogEvent(AuditEvents.RecoveryCodesRegenerated, userId, callerDevice.Id,
            ipAddress: httpContext.Connection.RemoteIpAddress?.ToString());

        await db.SaveChangesAsync();
        return Results.Ok(new RecoveryCodeRegenerateResponse(DateTime.UtcNow));
    }

    public static async Task<IResult> CancelRecovery(
        Guid sessionId,
        ClaimsPrincipal user,
        AppDbContext db,
        IAuditService audit,
        HttpContext httpContext)
    {
        var userId = DeviceAuthHelper.GetUserId(user);
        var callerDevice = await DeviceAuthHelper.GetApprovedCallerDevice(user, db);
        if (callerDevice is null)
            return Results.Forbid();

        var session = await db.RecoverySessions.FirstOrDefaultAsync(s =>
            s.Id == sessionId && s.UserId == userId
            && (s.Status == RecoverySessionStatus.Pending || s.Status == RecoverySessionStatus.Ready));

        if (session is null)
            return Results.NotFound();

        session.Status = RecoverySessionStatus.Cancelled;
        session.CancelledAt = DateTime.UtcNow;

        audit.LogEvent(AuditEvents.RecoverySessionCancelled, userId, callerDevice.Id,
            eventData: new { RecoverySessionId = session.Id },
            ipAddress: httpContext.Connection.RemoteIpAddress?.ToString());

        await db.SaveChangesAsync();
        return Results.Ok();
    }
}
