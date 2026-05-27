namespace PsTotp.Server.Api.Filters;

/// <summary>
/// Validates the Origin header on state-changing requests (POST/PUT/DELETE) when
/// the request is authenticated via cookies (not Bearer tokens).
/// Defense-in-depth alongside SameSite=Strict cookies.
///
/// The allow-list is computed once at construction from
/// <see cref="AuthConstants.ResolveAllowedOrigins"/> (configured AllowedOrigins or
/// the env-appropriate default unioned with the application's actual listen URLs).
/// Rejections return a JSON body identifying the observed origin so the SPA can
/// show something better than a generic "request failed" toast.
/// </summary>
public class OriginValidationFilter(IConfiguration configuration, IHostEnvironment env) : IEndpointFilter
{
    private readonly string[] _allowedOrigins = AuthConstants.ResolveAllowedOrigins(configuration, env.IsDevelopment())
        .Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

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
                    return Reject(observed: null);

                if (!IsAllowedOrigin(referer))
                    return Reject(observed: NormaliseOrigin(referer));
            }
            else if (!IsAllowedOrigin(origin))
            {
                return Reject(observed: origin);
            }
        }

        return await next(context);
    }

    private static IResult Reject(string? observed)
    {
        return Results.Json(
            new { Error = AuthConstants.ErrorOriginNotAllowed, Origin = observed },
            statusCode: 403);
    }

    private bool IsAllowedOrigin(string originOrReferer)
    {
        if (!Uri.TryCreate(originOrReferer, UriKind.Absolute, out var requestUri))
            return false;

        var requestOrigin = $"{requestUri.Scheme}://{requestUri.Authority}";

        foreach (var allowed in _allowedOrigins)
        {
            if (requestOrigin.Equals(allowed, StringComparison.OrdinalIgnoreCase))
                return true;
        }

        return false;
    }

    private static string? NormaliseOrigin(string originOrReferer)
    {
        return Uri.TryCreate(originOrReferer, UriKind.Absolute, out var uri)
            ? $"{uri.Scheme}://{uri.Authority}"
            : null;
    }
}
