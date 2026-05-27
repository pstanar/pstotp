using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using PsTotp.Server.Application.Services;
using PsTotp.Server.Infrastructure.Services;

namespace PsTotp.Server.Infrastructure;

public static class DependencyInjection
{
    /// <summary>
    /// Registers infrastructure services. <paramref name="fallbackOrigins"/> is
    /// the resolved CORS / cookie allow-list (typically computed by
    /// <c>AuthConstants.ResolveAllowedOrigins</c>) — used as the
    /// <c>Fido2:Origins</c> fallback when that section isn't explicitly set,
    /// so passkey enrollment / login don't silently break on non-default-port
    /// deployments. Pass <c>null</c> to keep the legacy behaviour that reads
    /// <c>AllowedOrigins</c> from config directly.
    /// </summary>
    public static IServiceCollection AddInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration,
        string? fallbackOrigins = null)
    {
        services.AddScoped<IAuditService, AuditService>();
        services.AddScoped<ITokenService, TokenService>();
        services.AddScoped<IServerSettingsService, ServerSettingsService>();
        services.AddSingleton<IRateLimiter, RateLimiter>();

        // HttpClient for the icon-proxy endpoint. Short timeout; generic user-agent.
        // Auto-redirect is disabled to prevent SSRF via a malicious 302 to a
        // private-range IP (e.g. 169.254.169.254 cloud metadata); the endpoint
        // handles redirects manually and re-validates each hop.
        services.AddHttpClient("icon-proxy", client =>
        {
            client.Timeout = TimeSpan.FromSeconds(5);
            client.DefaultRequestHeaders.UserAgent.ParseAdd("PsTotp-IconProxy/1.0");
        }).ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler
        {
            AllowAutoRedirect = false,
        });

        if (!string.IsNullOrEmpty(configuration["Email:SmtpHost"]))
            services.AddSingleton<IEmailService, SmtpEmailService>();
        else
            services.AddSingleton<IEmailService, NullEmailService>();
        services.AddHostedService<SessionCleanupService>();

        var fido2Domain = configuration["Fido2:ServerDomain"] ?? "localhost";

        var fido2Origins = configuration.GetSection("Fido2:Origins").Get<HashSet<string>>();
        if (fido2Origins is null || fido2Origins.Count == 0)
        {
            // Fall back through (in order):
            //   1. The resolved AllowedOrigins from the caller — already
            //      unions the listen URLs, so passkeys work on a custom
            //      port without any extra config.
            //   2. Legacy: raw "AllowedOrigins" config (kept for tests /
            //      consumers that don't pass fallbackOrigins).
            //   3. Hard-coded localhost:5000.
            var corsOrigins = fallbackOrigins ?? configuration.GetValue<string>("AllowedOrigins");
            fido2Origins = !string.IsNullOrEmpty(corsOrigins)
                ? corsOrigins.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).ToHashSet()
                : ["http://localhost:5000"];
        }

        // Auto-add Android passkey origins from configured cert fingerprints.
        // CertFingerprints are SHA-256 of the signing cert in colon-separated hex (e.g. "14:6D:E9:...").
        // The android:apk-key-hash origin is the same bytes encoded as base64url.
        var certFingerprints = configuration.GetSection("Android:CertFingerprints").Get<string[]>();
        if (certFingerprints is { Length: > 0 })
        {
            foreach (var fp in certFingerprints)
            {
                var bytes = Convert.FromHexString(fp.Replace(":", ""));
                var base64Url = Convert.ToBase64String(bytes)
                    .Replace('+', '-').Replace('/', '_').TrimEnd('=');
                fido2Origins.Add($"android:apk-key-hash:{base64Url}");
            }
        }

        services.AddFido2(options =>
        {
            options.ServerDomain = fido2Domain;
            options.ServerName = configuration["Fido2:ServerName"] ?? "PsTotp";
            options.Origins = fido2Origins;
        });

        return services;
    }
}
