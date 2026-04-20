using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using PsTotp.Server.Application.DTOs;
using PsTotp.Server.Application.Services;
using PsTotp.Server.Domain.Entities;
using PsTotp.Server.Infrastructure.Data;

namespace PsTotp.Server.Api.EndPoints;

public static class AdminEndpoints
{
    public static async Task<IResult> ListUsers(
        AppDbContext db,
        HttpContext httpContext)
    {
        var search = httpContext.Request.Query["search"].FirstOrDefault()?.ToLower();

        var query = db.Users.AsQueryable();
        if (!string.IsNullOrEmpty(search))
            query = query.Where(u => u.Email.ToLower().Contains(search));

        var totalCount = await query.CountAsync();
        var users = await query
            .OrderBy(u => u.Email)
            .Select(u => new AdminUserDto(
                u.Id,
                u.Email,
                u.Role.ToString(),
                u.CreatedAt,
                u.LastLoginAt,
                u.DisabledAt,
                u.ForcePasswordReset,
                u.Devices.Count(d => d.Status != DeviceStatus.Revoked),
                u.VaultEntries.Count(e => e.DeletedAt == null),
                u.WebAuthnCredentials.Count(c => c.RevokedAt == null)))
            .ToListAsync();

        return Results.Ok(new AdminUserListResponse(users, totalCount));
    }

    public static async Task<IResult> GetUserDetail(
        Guid userId,
        AppDbContext db)
    {
        var user = await db.Users
            .Where(u => u.Id == userId)
            .Select(u => new AdminUserDto(
                u.Id,
                u.Email,
                u.Role.ToString(),
                u.CreatedAt,
                u.LastLoginAt,
                u.DisabledAt,
                u.ForcePasswordReset,
                u.Devices.Count(d => d.Status != DeviceStatus.Revoked),
                u.VaultEntries.Count(e => e.DeletedAt == null),
                u.WebAuthnCredentials.Count(c => c.RevokedAt == null)))
            .FirstOrDefaultAsync();

        if (user is null)
            return Results.NotFound();

        var devices = await db.Devices
            .Where(d => d.UserId == userId)
            .OrderByDescending(d => d.CreatedAt)
            .Select(d => new AdminDeviceDto(
                d.Id,
                d.DeviceName,
                d.Platform,
                d.Status.ToString(),
                d.CreatedAt,
                d.ApprovedAt,
                d.RevokedAt,
                d.LastSeenAt))
            .ToListAsync();

        var recoverySessions = await db.RecoverySessions
            .Where(s => s.UserId == userId
                && (s.Status == RecoverySessionStatus.Pending || s.Status == RecoverySessionStatus.Ready)
                && s.ExpiresAt > DateTime.UtcNow)
            .OrderByDescending(s => s.CreatedAt)
            .Select(s => new AdminRecoverySessionDto(
                s.Id,
                s.Status.ToString(),
                s.CreatedAt,
                s.ExpiresAt,
                s.ReleaseEarliestAt))
            .ToListAsync();

        return Results.Ok(new AdminUserDetailResponse(user, devices, recoverySessions));
    }

    public static async Task<IResult> DisableUser(
        Guid userId,
        ClaimsPrincipal principal,
        AppDbContext db,
        IAuditService audit,
        ITokenService tokenService,
        HttpContext httpContext)
    {
        var adminId = DeviceAuthHelper.GetUserId(principal);
        if (userId == adminId)
            return Results.BadRequest(new { Error = "Cannot disable your own account" });

        var user = await db.Users.FirstOrDefaultAsync(u => u.Id == userId);
        if (user is null)
            return Results.NotFound();

        await using var transaction = await db.Database.BeginTransactionAsync();

        user.DisabledAt = DateTime.UtcNow;

        audit.LogEvent(AuditEvents.UserDisabled, userId,
            eventData: new { user.Email, DisabledBy = adminId },
            ipAddress: httpContext.Connection.RemoteIpAddress?.ToString());

        await tokenService.RevokeAllUserTokensAsync(userId);
        await db.SaveChangesAsync();
        await transaction.CommitAsync();

        return Results.Ok();
    }

    public static async Task<IResult> EnableUser(
        Guid userId,
        ClaimsPrincipal principal,
        AppDbContext db,
        IAuditService audit,
        HttpContext httpContext)
    {
        var adminId = DeviceAuthHelper.GetUserId(principal);
        var user = await db.Users.FirstOrDefaultAsync(u => u.Id == userId);
        if (user is null)
            return Results.NotFound();

        user.DisabledAt = null;

        audit.LogEvent(AuditEvents.UserEnabled, userId,
            eventData: new { user.Email, EnabledBy = adminId },
            ipAddress: httpContext.Connection.RemoteIpAddress?.ToString());

        await db.SaveChangesAsync();
        return Results.Ok();
    }

    public static async Task<IResult> ForcePasswordReset(
        Guid userId,
        ClaimsPrincipal principal,
        AppDbContext db,
        IAuditService audit,
        HttpContext httpContext)
    {
        var adminId = DeviceAuthHelper.GetUserId(principal);
        var user = await db.Users.FirstOrDefaultAsync(u => u.Id == userId);
        if (user is null)
            return Results.NotFound();

        user.ForcePasswordReset = true;

        audit.LogEvent(AuditEvents.ForcePasswordResetSet, userId,
            eventData: new { user.Email, SetBy = adminId },
            ipAddress: httpContext.Connection.RemoteIpAddress?.ToString());

        await db.SaveChangesAsync();
        return Results.Ok();
    }

    public static async Task<IResult> DeleteUser(
        Guid userId,
        ClaimsPrincipal principal,
        AppDbContext db,
        IAuditService audit,
        ITokenService tokenService,
        HttpContext httpContext)
    {
        var adminId = DeviceAuthHelper.GetUserId(principal);
        if (userId == adminId)
            return Results.BadRequest(new { Error = "Cannot delete your own account" });

        var user = await db.Users.FirstOrDefaultAsync(u => u.Id == userId);
        if (user is null)
            return Results.NotFound();

        var email = user.Email;

        await using var transaction = await db.Database.BeginTransactionAsync();

        // No revocation needed — tokens are bulk-deleted below
        await db.AuditEvents.Where(e => e.UserId == userId).ExecuteDeleteAsync();
        await db.WebAuthnCredentials.Where(c => c.UserId == userId).ExecuteDeleteAsync();
        await db.WebAuthnCeremonies.Where(c => c.UserId == userId).ExecuteDeleteAsync();
        await db.RecoveryCodes.Where(c => c.UserId == userId).ExecuteDeleteAsync();
        await db.RecoverySessions.Where(s => s.UserId == userId).ExecuteDeleteAsync();
        await db.VaultKeyEnvelopes.Where(e => e.UserId == userId).ExecuteDeleteAsync();
        await db.VaultEntries.Where(e => e.UserId == userId).ExecuteDeleteAsync();
        await db.RefreshTokens.Where(t => t.UserId == userId).ExecuteDeleteAsync();
        await db.Devices.Where(d => d.UserId == userId).ExecuteDeleteAsync();
        await db.Users.Where(u => u.Id == userId).ExecuteDeleteAsync();

        audit.LogEvent(AuditEvents.UserDeleted, adminId,
            eventData: new { DeletedUserId = userId, DeletedEmail = email },
            ipAddress: httpContext.Connection.RemoteIpAddress?.ToString());

        await db.SaveChangesAsync();
        await transaction.CommitAsync();
        return Results.Ok();
    }

    public static async Task<IResult> CancelRecoverySession(
        Guid userId,
        Guid sessionId,
        ClaimsPrincipal principal,
        AppDbContext db,
        IAuditService audit,
        HttpContext httpContext)
    {
        var adminId = DeviceAuthHelper.GetUserId(principal);

        var session = await db.RecoverySessions.FirstOrDefaultAsync(s =>
            s.Id == sessionId && s.UserId == userId
            && (s.Status == RecoverySessionStatus.Pending || s.Status == RecoverySessionStatus.Ready));

        if (session is null)
            return Results.NotFound();

        session.Status = RecoverySessionStatus.Cancelled;
        session.CancelledAt = DateTime.UtcNow;

        audit.LogEvent(AuditEvents.RecoverySessionCancelled, userId,
            eventData: new { RecoverySessionId = sessionId, CancelledBy = adminId },
            ipAddress: httpContext.Connection.RemoteIpAddress?.ToString());

        await db.SaveChangesAsync();
        return Results.Ok();
    }
}
