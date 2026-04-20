using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using PsTotp.Server.Application.DTOs;
using PsTotp.Server.Application.Services;
using PsTotp.Server.Domain.Entities;
using PsTotp.Server.Infrastructure.Data;

namespace PsTotp.Server.Api.EndPoints;

public static class DeviceEndpoints
{
    public static async Task<IResult> ListDevices(
        ClaimsPrincipal user,
        AppDbContext db)
    {
        var userId = DeviceAuthHelper.GetUserId(user);

        // Newest approval first. Pending devices (no ApprovedAt) fall to the
        // bottom via the HasValue sort — the clients either bucket pending
        // separately (web) or show them inline (Android), so putting them
        // last is the least surprising option in both UIs.
        var devices = await db.Devices
            .Where(d => d.UserId == userId)
            .OrderByDescending(d => d.ApprovedAt.HasValue)
            .ThenByDescending(d => d.ApprovedAt)
            .ThenByDescending(d => d.CreatedAt)
            .Select(d => new DeviceInfoDto(
                d.Id,
                d.DeviceName,
                d.Platform,
                d.Status.ToString().ToLowerInvariant(),
                d.ApprovedAt,
                d.Status == DeviceStatus.Pending ? d.Id : null,
                d.Status == DeviceStatus.Pending ? d.DevicePublicKey : null,
                d.Status == DeviceStatus.Pending ? d.CreatedAt : null,
                d.RevokedAt))
            .ToListAsync();

        return Results.Ok(new DeviceListResponse(devices));
    }

    public static async Task<IResult> ApproveDevice(
        Guid deviceId,
        ApproveDeviceRequest request,
        ClaimsPrincipal user,
        AppDbContext db,
        IAuditService audit,
        HttpContext httpContext)
    {
        var userId = DeviceAuthHelper.GetUserId(user);
        var callerDeviceId = DeviceAuthHelper.GetDeviceId(user);

        // Verify the caller is on an approved device
        var callerDevice = await db.Devices.FirstOrDefaultAsync(d =>
            d.Id == callerDeviceId && d.UserId == userId && d.Status == DeviceStatus.Approved);
        if (callerDevice is null)
            return Results.Forbid();

        var pendingDevice = await db.Devices.FirstOrDefaultAsync(d =>
            d.Id == deviceId && d.UserId == userId && d.Status == DeviceStatus.Pending);
        if (pendingDevice is null)
            return Results.NotFound();

        pendingDevice.Status = DeviceStatus.Approved;
        pendingDevice.ApprovedAt = DateTime.UtcNow;

        // Store the device envelope
        var envelope = new VaultKeyEnvelope
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            DeviceId = deviceId,
            EnvelopeType = EnvelopeType.Device,
            WrappedKeyPayload = EnvelopeHelper.ToBytes(request.DeviceEnvelope),
            CreatedAt = DateTime.UtcNow,
        };
        db.VaultKeyEnvelopes.Add(envelope);

        audit.LogEvent(AuditEvents.DeviceApproved, userId, deviceId,
            new { pendingDevice.DeviceName, ApprovedBy = callerDevice.DeviceName },
            httpContext.Connection.RemoteIpAddress?.ToString());

        await db.SaveChangesAsync();
        return Results.Ok(new ApproveDeviceResponse(deviceId, "approved"));
    }

    public static async Task<IResult> RejectDevice(
        Guid deviceId,
        ClaimsPrincipal user,
        AppDbContext db,
        IAuditService audit,
        ITokenService tokenService,
        HttpContext httpContext)
    {
        var userId = DeviceAuthHelper.GetUserId(user);

        // Caller must be on an approved device (same check as ApproveDevice)
        var callerDeviceId = DeviceAuthHelper.GetDeviceId(user);
        var callerDevice = await db.Devices.FirstOrDefaultAsync(d =>
            d.Id == callerDeviceId && d.UserId == userId && d.Status == DeviceStatus.Approved);
        if (callerDevice is null)
            return Results.Forbid();

        var pendingDevice = await db.Devices.FirstOrDefaultAsync(d =>
            d.Id == deviceId && d.UserId == userId && d.Status == DeviceStatus.Pending);

        if (pendingDevice is null)
            return Results.NotFound();

        await using var transaction = await db.Database.BeginTransactionAsync();

        pendingDevice.Status = DeviceStatus.Revoked;
        pendingDevice.RevokedAt = DateTime.UtcNow;

        audit.LogEvent(AuditEvents.DeviceRejected, userId, deviceId,
            eventData: new { pendingDevice.DeviceName },
            ipAddress: httpContext.Connection.RemoteIpAddress?.ToString());

        await tokenService.RevokeAllDeviceTokensAsync(userId, deviceId);
        await db.SaveChangesAsync();
        await transaction.CommitAsync();

        return Results.Ok();
    }

    public static async Task<IResult> RevokeDevice(
        Guid deviceId,
        ClaimsPrincipal user,
        AppDbContext db,
        IAuditService audit,
        ITokenService tokenService,
        HttpContext httpContext)
    {
        var userId = DeviceAuthHelper.GetUserId(user);

        // Verify caller is on an approved device
        var callerDeviceId = DeviceAuthHelper.GetDeviceId(user);
        var callerDevice = await db.Devices.FirstOrDefaultAsync(d =>
            d.Id == callerDeviceId && d.UserId == userId && d.Status == DeviceStatus.Approved);
        if (callerDevice is null)
            return Results.Forbid();

        var device = await db.Devices.FirstOrDefaultAsync(d =>
            d.Id == deviceId && d.UserId == userId && d.Status == DeviceStatus.Approved);
        if (device is null)
            return Results.NotFound();

        await using var transaction = await db.Database.BeginTransactionAsync();

        device.Status = DeviceStatus.Revoked;
        device.RevokedAt = DateTime.UtcNow;

        var envelope = await db.VaultKeyEnvelopes.FirstOrDefaultAsync(e =>
            e.DeviceId == deviceId && e.UserId == userId && e.EnvelopeType == EnvelopeType.Device && e.RevokedAt == null);
        envelope?.RevokedAt = DateTime.UtcNow;

        audit.LogEvent(AuditEvents.DeviceRevoked, userId, deviceId,
            eventData: new { device.DeviceName },
            ipAddress: httpContext.Connection.RemoteIpAddress?.ToString());

        await tokenService.RevokeAllDeviceTokensAsync(userId, deviceId);
        await db.SaveChangesAsync();
        await transaction.CommitAsync();

        return Results.Ok();
    }

    public static async Task<IResult> UpdateSelfEnvelope(
        EnvelopeDto request,
        ClaimsPrincipal user,
        AppDbContext db)
    {
        var callerDevice = await DeviceAuthHelper.GetApprovedCallerDevice(user, db);
        if (callerDevice is null)
            return Results.Forbid();

        var userId = DeviceAuthHelper.GetUserId(user);
        var deviceId = callerDevice.Id;

        await using var transaction = await db.Database.BeginTransactionAsync();

        await db.VaultKeyEnvelopes
            .Where(e => e.UserId == userId && e.DeviceId == deviceId && e.EnvelopeType == EnvelopeType.Device)
            .ExecuteDeleteAsync();

        db.VaultKeyEnvelopes.Add(new VaultKeyEnvelope
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            DeviceId = deviceId,
            EnvelopeType = EnvelopeType.Device,
            WrappedKeyPayload = EnvelopeHelper.ToBytes(request),
            CreatedAt = DateTime.UtcNow,
        });

        await db.SaveChangesAsync();
        await transaction.CommitAsync();
        return Results.Ok();
    }

}
