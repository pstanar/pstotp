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
    public const string ErrorOriginNotAllowed = "Origin not allowed";

    public const string DefaultListenUrl = "http://0.0.0.0:5000";
    public const string DefaultProductionOrigin = "http://localhost:5000;https://localhost:5001";
    public const string DefaultDevelopmentOrigin = "http://localhost:5173";

    /// <summary>
    /// Resolve allowed origins from config, falling back to environment-appropriate
    /// defaults UNIONED with the application's actual listen URLs. Custom-port
    /// deployments (ASPNETCORE_URLS=http://localhost:5245) get their origin allowed
    /// for free; operators who explicitly set AllowedOrigins still get exactly the
    /// list they asked for (no auto-include, because the explicit list is treated
    /// as the operator's intent).
    /// </summary>
    public static string ResolveAllowedOrigins(IConfiguration configuration, bool isDevelopment)
    {
        var configured = configuration.GetValue<string>("AllowedOrigins");
        if (!string.IsNullOrEmpty(configured))
            return configured;

        var defaults = isDevelopment ? DefaultDevelopmentOrigin : DefaultProductionOrigin;
        var listenOrigins = ResolveListenOrigins(configuration);
        if (listenOrigins.Count == 0)
            return defaults;

        var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var origin in defaults.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            set.Add(origin);
        foreach (var origin in listenOrigins)
            set.Add(origin);

        return string.Join(';', set);
    }

    /// <summary>
    /// Resolve the origins (scheme://host:port) the application is configured to
    /// listen on. Reads from the standard ASP.NET Core "Urls" config key
    /// (populated by ASPNETCORE_URLS env var, --urls CLI arg, or WebHost.UseUrls)
    /// and the "Kestrel:Endpoints" section. Wildcard hosts (0.0.0.0, [::], *, +)
    /// are normalised to "localhost" because that's what a browser will send as
    /// the Origin header.
    /// </summary>
    public static IReadOnlyList<string> ResolveListenOrigins(IConfiguration configuration)
    {
        var urls = new List<string>();

        var configured = configuration.GetValue<string>("Urls");
        if (!string.IsNullOrEmpty(configured))
            urls.Add(configured);

        foreach (var endpoint in configuration.GetSection("Kestrel:Endpoints").GetChildren())
        {
            var url = endpoint.GetValue<string>("Url");
            if (!string.IsNullOrEmpty(url))
                urls.Add(url);
        }

        var origins = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var urlList in urls)
        {
            foreach (var url in urlList.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            {
                // Kestrel's bind-all sentinels (* and +) aren't valid URI hosts
                // per RFC 3986 — pre-substitute so Uri.TryCreate doesn't drop
                // the whole entry. 0.0.0.0 and [::] parse fine and get fixed
                // up post-parse below.
                var normalised = url
                    .Replace("://*:", "://localhost:", StringComparison.Ordinal)
                    .Replace("://+:", "://localhost:", StringComparison.Ordinal);

                if (!Uri.TryCreate(normalised, UriKind.Absolute, out var uri))
                    continue;
                var host = uri.Host;
                if (host is "0.0.0.0" or "[::]")
                    host = "localhost";
                origins.Add($"{uri.Scheme}://{host}:{uri.Port}");
            }
        }

        return origins.ToList();
    }
}
