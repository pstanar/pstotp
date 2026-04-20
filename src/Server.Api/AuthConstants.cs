namespace PsTotp.Server.Api;

public static class AuthConstants
{
    public const string AccessTokenCookieName = "__Host-access_token";
    public const string RefreshTokenCookieName = "__Host-refresh_token";
    public const string RefreshTokenCookiePath = "/"; // __Host- prefix requires Path=/
    public const string WebClientType = "web";
    public const string UserPolicy = "UserPolicy";
    public const string AdminPolicy = "AdminPolicy";

    public const string ErrorAccountDisabled = "Account is disabled";
    public const string ErrorPasswordResetRequired = "Password reset required";

    public const string DefaultListenUrl = "http://0.0.0.0:5000";
    public const string DefaultProductionOrigin = "http://localhost:5000;https://localhost:5001";
    public const string DefaultDevelopmentOrigin = "http://localhost:5173";

    /// <summary>
    /// Resolve allowed origins from config, falling back to environment-appropriate defaults.
    /// </summary>
    public static string ResolveAllowedOrigins(IConfiguration configuration, bool isDevelopment)
    {
        return configuration.GetValue<string>("AllowedOrigins")
            ?? (isDevelopment ? DefaultDevelopmentOrigin : DefaultProductionOrigin);
    }
}
