using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using PsTotp.Server.Application.Services;
using PsTotp.Server.Infrastructure.Services;

namespace PsTotp.Server.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddInfrastructure(this IServiceCollection services, IConfiguration configuration)
    {
        services.AddScoped<IAuditService, AuditService>();
        services.AddScoped<ITokenService, TokenService>();
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
            // Derive from AllowedOrigins (CORS config), or fall back to default
            var corsOrigins = configuration.GetValue<string>("AllowedOrigins");
            fido2Origins = !string.IsNullOrEmpty(corsOrigins)
                ? corsOrigins.Split(';').ToHashSet()
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
