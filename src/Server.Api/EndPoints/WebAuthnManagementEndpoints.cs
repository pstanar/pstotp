using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using PsTotp.Server.Application.DTOs;
using PsTotp.Server.Application.Services;
using PsTotp.Server.Infrastructure.Data;

namespace PsTotp.Server.Api.EndPoints;

public static class WebAuthnManagementEndpoints
{
    public static async Task<IResult> ListCredentials(
        ClaimsPrincipal principal,
        AppDbContext db)
    {
        var userId = DeviceAuthHelper.GetUserId(principal);
        var callerDevice = await DeviceAuthHelper.GetApprovedCallerDevice(principal, db);
        if (callerDevice is null)
            return Results.Forbid();

        var credentials = await db.WebAuthnCredentials
            .Where(c => c.UserId == userId && c.RevokedAt == null)
            .OrderByDescending(c => c.CreatedAt)
            .Select(c => new WebAuthnCredentialDto(c.Id, c.FriendlyName, c.CreatedAt, c.LastUsedAt))
            .ToListAsync();

        return Results.Ok(new WebAuthnCredentialListResponse(credentials));
    }

    public static async Task<IResult> RenameCredential(
        Guid credentialId,
        WebAuthnRenameRequest request,
        ClaimsPrincipal principal,
        AppDbContext db)
    {
        var userId = DeviceAuthHelper.GetUserId(principal);
        var callerDevice = await DeviceAuthHelper.GetApprovedCallerDevice(principal, db);
        if (callerDevice is null)
            return Results.Forbid();

        var credential = await db.WebAuthnCredentials.FirstOrDefaultAsync(c =>
            c.Id == credentialId && c.UserId == userId && c.RevokedAt == null);
        if (credential is null)
            return Results.NotFound();

        credential.FriendlyName = request.FriendlyName.Trim();
        await db.SaveChangesAsync();

        return Results.Ok();
    }

    public static async Task<IResult> RevokeCredential(
        Guid credentialId,
        ClaimsPrincipal principal,
        AppDbContext db,
        IAuditService audit,
        HttpContext httpContext)
    {
        var userId = DeviceAuthHelper.GetUserId(principal);
        var callerDevice = await DeviceAuthHelper.GetApprovedCallerDevice(principal, db);
        if (callerDevice is null)
            return Results.Forbid();

        var credential = await db.WebAuthnCredentials.FirstOrDefaultAsync(c =>
            c.Id == credentialId && c.UserId == userId && c.RevokedAt == null);
        if (credential is null)
            return Results.NotFound();

        credential.RevokedAt = DateTime.UtcNow;

        audit.LogEvent(AuditEvents.WebAuthnCredentialRevoked, userId, callerDevice.Id,
            eventData: new { CredentialId = credentialId, credential.FriendlyName },
            ipAddress: httpContext.Connection.RemoteIpAddress?.ToString());

        await db.SaveChangesAsync();
        return Results.Ok();
    }
}
