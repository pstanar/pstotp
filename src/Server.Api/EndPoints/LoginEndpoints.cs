using System.Security.Cryptography;
using Microsoft.EntityFrameworkCore;
using PsTotp.Server.Application.Crypto;
using PsTotp.Server.Application.DTOs;
using PsTotp.Server.Application.Services;
using PsTotp.Server.Domain.Entities;
using PsTotp.Server.Infrastructure.Data;

namespace PsTotp.Server.Api.EndPoints;

public static class LoginEndpoints
{
    public static async Task<IResult> Login(
        LoginRequest request,
        AppDbContext db,
        IAuditService audit,
        HttpContext httpContext)
    {
        var user = await db.Users.FirstOrDefaultAsync(u => u.Email == request.Email);
        var nonce = PasswordVerifier.GenerateNonce();
        var sessionId = Guid.NewGuid();

        var kdfConfig = user != null
            ? System.Text.Json.JsonSerializer.Deserialize<KdfConfigDto>(user.PasswordKdfConfig)!
            : new KdfConfigDto("argon2id", 64, 3, 4, Convert.ToBase64String(RandomNumberGenerator.GetBytes(16)));

        Guid? deviceId = null;
        if (user != null)
        {
            Device? existingDevice = null;

            if (!string.IsNullOrEmpty(request.Device.DevicePublicKey))
            {
                existingDevice = await db.Devices.FirstOrDefaultAsync(d =>
                    d.UserId == user.Id && d.DevicePublicKey == request.Device.DevicePublicKey && d.Status != DeviceStatus.Revoked);

                existingDevice?.DeviceName = request.Device.DeviceName;
            }

            if (existingDevice != null)
            {
                deviceId = existingDevice.Id;
            }
            else
            {
                var device = new Device
                {
                    Id = Guid.NewGuid(),
                    UserId = user.Id,
                    DeviceName = request.Device.DeviceName,
                    Platform = request.Device.Platform,
                    ClientType = request.Device.ClientType,
                    Status = DeviceStatus.Pending,
                    DevicePublicKey = request.Device.DevicePublicKey,
                    CreatedAt = DateTime.UtcNow,
                };
                db.Devices.Add(device);
                deviceId = device.Id;
            }
        }

        var session = new LoginSession
        {
            Id = sessionId,
            Email = request.Email,
            Nonce = nonce,
            CreatedAt = DateTime.UtcNow,
            ExpiresAt = DateTime.UtcNow.AddMinutes(5),
            DeviceId = deviceId,
        };
        db.LoginSessions.Add(session);
        await db.SaveChangesAsync();

        return Results.Ok(new LoginChallengeResponse(
            sessionId,
            new LoginChallenge(Convert.ToBase64String(nonce), kdfConfig)));
    }

    public static async Task<IResult> CompleteLogin(
        LoginCompleteRequest request,
        AppDbContext db,
        ITokenService tokenService,
        IAuditService audit,
        IRateLimiter rateLimiter,
        IConfiguration configuration,
        HttpContext httpContext)
    {
        var session = await db.LoginSessions.FirstOrDefaultAsync(s =>
            s.Id == request.LoginSessionId && !s.IsCompleted && s.ExpiresAt > DateTime.UtcNow);

        if (session is null)
            return Results.Unauthorized();

        if (rateLimiter.IsRateLimited(session.Email, Application.SharedConstants.RateLimitLogin))
            return Results.StatusCode(429);

        var user = await db.Users.FirstOrDefaultAsync(u => u.Email == session.Email);
        if (user is null)
            return Results.Unauthorized();

        var clientProofBytes = Convert.FromBase64String(request.ClientProof);
        if (!PasswordVerifier.VerifyClientProof(user.PasswordVerifier, session.Nonce, session.Id, clientProofBytes))
        {
            rateLimiter.RecordAttempt(session.Email, Application.SharedConstants.RateLimitLogin);
            audit.LogEvent(AuditEvents.LoginFailed, user.Id,
                eventData: new { user.Email },
                ipAddress: httpContext.Connection.RemoteIpAddress?.ToString());
            await db.SaveChangesAsync();
            return Results.Unauthorized();
        }

        session.IsCompleted = true;

        if (user.DisabledAt.HasValue)
            return Results.Json(new { Error = AuthConstants.ErrorAccountDisabled }, statusCode: 403);

        var adminEmails = configuration.GetSection("Admins").Get<string[]>() ?? [];
        var shouldBeAdmin = adminEmails.Contains(user.Email, StringComparer.OrdinalIgnoreCase);
        user.Role = shouldBeAdmin ? UserRole.Admin : UserRole.User;

        user.LastLoginAt = DateTime.UtcNow;

        var device = session.DeviceId.HasValue
            ? await db.Devices.FirstOrDefaultAsync(d => d.Id == session.DeviceId.Value)
            : null;

        if (device is null)
            return Results.Unauthorized();

        device.LastSeenAt = DateTime.UtcNow;

        var roleStr = user.Role == UserRole.Admin ? Application.SharedConstants.AdminRole : null;
        var accessToken = tokenService.GenerateAccessToken(user.Id, user.Email, device.Id, roleStr);
        var (refreshToken, _) = await tokenService.GenerateRefreshTokenAsync(user.Id, device.Id);

        audit.LogEvent(AuditEvents.LoginSuccess, user.Id, device.Id,
            eventData: new { device.DeviceName },
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
