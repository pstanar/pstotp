namespace PsTotp.Server.Application.Services;

public interface ITokenService
{
    string GenerateAccessToken(Guid userId, string email, Guid deviceId, string? role = null);
    Task<(string token, Guid tokenId)> GenerateRefreshTokenAsync(Guid userId, Guid deviceId);
    Task<(string accessToken, string refreshToken)?> RotateRefreshTokenAsync(string refreshToken);
    Task RevokeRefreshTokenAsync(string refreshToken);
    Task RevokeAllUserTokensAsync(Guid userId);
    Task RevokeAllDeviceTokensAsync(Guid userId, Guid deviceId);
}
