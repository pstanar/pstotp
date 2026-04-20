using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.IdentityModel.Tokens;
using PsTotp.Server.Application.Services;
using PsTotp.Server.Domain.Entities;
using PsTotp.Server.Infrastructure.Data;

namespace PsTotp.Server.Infrastructure.Services;

public class TokenService(AppDbContext db, IConfiguration configuration) : ITokenService
{
    private const int RefreshTokenBytes = 64;
    private static readonly TimeSpan AccessTokenLifetime = TimeSpan.FromMinutes(15);
    private static readonly TimeSpan RefreshTokenLifetime = TimeSpan.FromDays(30);

    public string GenerateAccessToken(Guid userId, string email, Guid deviceId, string? role = null)
    {
        var key = GetSigningKey();
        var credentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, userId.ToString()),
            new(JwtRegisteredClaimNames.Email, email),
            new(Application.SharedConstants.DeviceIdClaim, deviceId.ToString()),
            new(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
        };

        if (!string.IsNullOrEmpty(role))
            claims.Add(new Claim(ClaimTypes.Role, role));

        var token = new JwtSecurityToken(
            issuer: configuration["Jwt:Issuer"] ?? Application.SharedConstants.DefaultJwtIssuer,
            audience: configuration["Jwt:Audience"] ?? Application.SharedConstants.DefaultJwtAudience,
            claims: claims,
            expires: DateTime.UtcNow.Add(AccessTokenLifetime),
            signingCredentials: credentials);

        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    public async Task<(string token, Guid tokenId)> GenerateRefreshTokenAsync(Guid userId, Guid deviceId)
    {
        var tokenBytes = RandomNumberGenerator.GetBytes(RefreshTokenBytes);
        var token = Convert.ToBase64String(tokenBytes);
        var tokenHash = HashToken(token);

        var refreshToken = new RefreshToken
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            DeviceId = deviceId,
            TokenHash = tokenHash,
            CreatedAt = DateTime.UtcNow,
            ExpiresAt = DateTime.UtcNow.Add(RefreshTokenLifetime),
        };

        db.RefreshTokens.Add(refreshToken);
        // No SaveChangesAsync here — callers control persistence
        // (transactions in recovery, password change, password reset)

        return (token, refreshToken.Id);
    }

    public async Task<(string accessToken, string refreshToken)?> RotateRefreshTokenAsync(string refreshToken)
    {
        var tokenHash = HashToken(refreshToken);

        // Serializable isolation prevents concurrent rotation of the same token
        await using var transaction = await db.Database.BeginTransactionAsync(System.Data.IsolationLevel.Serializable);

        var stored = await db.RefreshTokens
            .Include(t => t.User)
            .FirstOrDefaultAsync(t => t.TokenHash == tokenHash);

        if (stored is null || stored.RevokedAt != null || stored.ExpiresAt < DateTime.UtcNow)
            return null;

        var device = await db.Devices.FirstOrDefaultAsync(d => d.Id == stored.DeviceId);
        if (device is null || device.Status == DeviceStatus.Revoked)
            return null;

        if (stored.User.DisabledAt.HasValue)
            return null;

        // Revoke old token
        stored.RevokedAt = DateTime.UtcNow;

        var roleStr = stored.User.Role == UserRole.Admin ? Application.SharedConstants.AdminRole : null;
        var accessToken = GenerateAccessToken(stored.UserId, stored.User.Email, stored.DeviceId, roleStr);
        var (newRefreshToken, newTokenId) = await GenerateRefreshTokenAsync(stored.UserId, stored.DeviceId);

        stored.ReplacedByTokenId = newTokenId;
        await db.SaveChangesAsync();
        await transaction.CommitAsync();

        return (accessToken, newRefreshToken);
    }

    // Revocation methods mark tokens but do NOT call SaveChangesAsync —
    // callers control persistence (transactions in disable/password change/etc.)

    public async Task RevokeRefreshTokenAsync(string refreshToken)
    {
        var tokenHash = HashToken(refreshToken);
        var stored = await db.RefreshTokens.FirstOrDefaultAsync(t => t.TokenHash == tokenHash);
        if (stored is { RevokedAt: null })
            stored.RevokedAt = DateTime.UtcNow;
    }

    public async Task RevokeAllUserTokensAsync(Guid userId)
    {
        var tokens = await db.RefreshTokens
            .Where(t => t.UserId == userId && t.RevokedAt == null)
            .ToListAsync();
        foreach (var token in tokens)
            token.RevokedAt = DateTime.UtcNow;
    }

    public async Task RevokeAllDeviceTokensAsync(Guid userId, Guid deviceId)
    {
        var tokens = await db.RefreshTokens
            .Where(t => t.UserId == userId && t.DeviceId == deviceId && t.RevokedAt == null)
            .ToListAsync();
        foreach (var token in tokens)
            token.RevokedAt = DateTime.UtcNow;
    }

    private SymmetricSecurityKey GetSigningKey()
    {
        var secret = configuration["Jwt:Secret"]
                     ?? throw new InvalidOperationException("JWT secret not configured.");
        return new SymmetricSecurityKey(Convert.FromBase64String(secret));
    }

    private static string HashToken(string token)
    {
        var bytes = Convert.FromBase64String(token);
        var hash = SHA256.HashData(bytes);
        return Convert.ToBase64String(hash);
    }
}
