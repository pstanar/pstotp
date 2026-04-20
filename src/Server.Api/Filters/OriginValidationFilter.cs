namespace PsTotp.Server.Api.Filters;

/// <summary>
/// Validates the Origin header on state-changing requests (POST/PUT/DELETE) when
/// the request is authenticated via cookies (not Bearer tokens).
/// Defense-in-depth alongside SameSite=Strict cookies.
/// </summary>
public class OriginValidationFilter(IConfiguration configuration, IHostEnvironment env) : IEndpointFilter
{
    public async ValueTask<object?> InvokeAsync(EndpointFilterInvocationContext context, EndpointFilterDelegate next)
    {
        var httpContext = context.HttpContext;
        var method = httpContext.Request.Method;

        // Only validate state-changing methods
        if (method is "GET" or "HEAD" or "OPTIONS")
            return await next(context);

        // Only validate cookie-authenticated requests (Bearer token requests skip this check)
        var authHeader = httpContext.Request.Headers.Authorization.ToString();
        if (!string.IsNullOrEmpty(authHeader) && authHeader.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
            return await next(context);

        // If authenticated via cookie, validate Origin header
        if (httpContext.Request.Cookies.ContainsKey(AuthConstants.AccessTokenCookieName))
        {
            var origin = httpContext.Request.Headers.Origin.ToString();
            if (string.IsNullOrEmpty(origin))
            {
                // No Origin header — allow if Referer matches (some browsers don't send Origin on same-origin)
                var referer = httpContext.Request.Headers.Referer.ToString();
                if (string.IsNullOrEmpty(referer))
                    return Results.StatusCode(403);

                if (!IsAllowedOrigin(referer))
                    return Results.StatusCode(403);
            }
            else if (!IsAllowedOrigin(origin))
            {
                return Results.StatusCode(403);
            }
        }

        return await next(context);
    }

    private bool IsAllowedOrigin(string originOrReferer)
    {
        if (!Uri.TryCreate(originOrReferer, UriKind.Absolute, out var requestUri))
            return false;

        var requestOrigin = $"{requestUri.Scheme}://{requestUri.Authority}";

        var allowedOrigins = AuthConstants.ResolveAllowedOrigins(configuration, env.IsDevelopment());

        foreach (var allowed in allowedOrigins.Split(';', StringSplitOptions.RemoveEmptyEntries))
        {
            if (requestOrigin.Equals(allowed.Trim(), StringComparison.OrdinalIgnoreCase))
                return true;
        }

        return false;
    }
}
