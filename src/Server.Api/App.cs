using System.Diagnostics;
using System.Security.Claims;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.EntityFrameworkCore;
using PsTotp.Server.Api.EndPoints;
using PsTotp.Server.Api.Middleware;
using PsTotp.Server.Infrastructure.Data;
using Scalar.AspNetCore;
using Serilog;

namespace PsTotp.Server.Api;

public static partial class App
{
    [LoggerMessage(Level = LogLevel.Warning,
        Message = "Configured AllowedOrigins [{Allowed}] doesn't include any of the listen URLs [{Listen}]. " +
                  "Cookie-authenticated browser requests from the SPA will be rejected by OriginValidationFilter " +
                  "(bare 403). Add the listen URL(s) to AllowedOrigins, or unset AllowedOrigins to fall back to " +
                  "the auto-resolved default.")]
    private static partial void LogAllowedOriginsMismatch(Microsoft.Extensions.Logging.ILogger logger, string allowed, string listen);

    public static void Configure(WebApplication app)
    {
        // OpenAPI export mode: when set, the host is being booted only to
        // hand its endpoint metadata to `dotnet-getdocument` so the build
        // can dump the OpenAPI schema. Any init step that would touch the
        // database (or any other external dependency the builder doesn't
        // have) must honor this flag — otherwise the schema regen gate in
        // build.sh / build.ps1 can't run in environments without a live
        // DB, including Dockerfile.build. If you add a new DB-touching
        // startup step, gate it on this flag too.
        var isOpenApiExport = app.Configuration["PSTOTP_OPENAPI_EXPORT"] == "1";

        WarnOnAllowedOriginsMismatch(app);

        // Reverse-proxy setup: honor X-Forwarded-Proto/Host/For so the app knows
        // the original scheme (https) and client IP. Must run before any
        // middleware that consumes these values (auth cookies, redirects).
        var forwardedOptions = new ForwardedHeadersOptions
        {
            ForwardedHeaders = ForwardedHeaders.XForwardedFor
                               | ForwardedHeaders.XForwardedProto
                               | ForwardedHeaders.XForwardedHost,
        };
        // Trust only configured proxy addresses (defaults to loopback). If you
        // deploy nginx on a different host, add its IP to ReverseProxy:KnownProxies.
        forwardedOptions.KnownIPNetworks.Clear();
        forwardedOptions.KnownProxies.Clear();
        var knownProxies = app.Configuration.GetSection("ReverseProxy:KnownProxies").Get<string[]>() ?? [];
        foreach (var proxy in knownProxies)
        {
            if (System.Net.IPAddress.TryParse(proxy, out var ip))
                forwardedOptions.KnownProxies.Add(ip);
        }
        if (forwardedOptions.KnownProxies.Count == 0)
        {
            forwardedOptions.KnownProxies.Add(System.Net.IPAddress.Loopback);
            forwardedOptions.KnownProxies.Add(System.Net.IPAddress.IPv6Loopback);
        }
        app.UseForwardedHeaders(forwardedOptions);

        // Serve the app under an optional path prefix (e.g. "/totp") so it can
        // run behind a reverse proxy that preserves the prefix in the upstream
        // request path. Leave empty to run at root.
        var basePath = (app.Configuration["BasePath"] ?? "").TrimEnd('/');
        if (!string.IsNullOrEmpty(basePath))
        {
            if (!basePath.StartsWith('/')) basePath = "/" + basePath;
            app.UsePathBase(basePath);
        }
        app.Configuration["_Resolved:BasePath"] = basePath;

        // Explicit UseRouting so WebApplication doesn't auto-insert it at the
        // start of the pipeline (which would run before UsePathBase and make
        // routing see the full /totp/... path, so only the fallback matches).
        app.UseRouting();

        // Cancel any pending browser-close shutdown when new requests arrive (handles page refresh)
        if (app.Configuration.GetValue<bool>("_Resolved:ShutdownEnabled"))
        {
            app.Use(async (context, next) =>
            {
                if (!context.Request.Path.StartsWithSegments("/api/system/closing"))
                    SystemEndpoints.CancelPendingShutdown();
                await next();
            });
        }
        // DB-touching startup work lives inside this block. Skipped under
        // isOpenApiExport (see the comment at the top of Configure).
        if (!isOpenApiExport)
        {
            using var scope = app.Services.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var isSqlite = db.Database.ProviderName == "Microsoft.EntityFrameworkCore.Sqlite";

            // SQLite: enable WAL journaling. WAL is a persistent per-file
            // setting, so this runs once and sticks. Matters most for the
            // small-hosted-SQLite case (multiple concurrent users / syncs),
            // but also helps single-user by letting the UI's parallel reads
            // proceed without blocking on an in-flight write.
            if (isSqlite && app.Environment.EnvironmentName != "Testing")
                db.Database.ExecuteSqlRaw("PRAGMA journal_mode=WAL;");

            // Auto-migrate rules:
            //   - Never in Testing.
            //   - Always for SQLite (the zero-config single-user case — users
            //     shouldn't have to know about migrations at all).
            //   - Always in Development (iterating on the schema).
            //   - For other providers in Production, only when the operator
            //     explicitly opts in via Database:ApplyMigrationsOnStartup.
            //     The recommended production path is still the out-of-band
            //     `PsTotp.Server.Api --migrate` step — see docs/DEPLOY.md.
            var applyOnStartup = app.Configuration.GetValue("Database:ApplyMigrationsOnStartup", false);
            if ((app.Environment.IsDevelopment() || isSqlite || applyOnStartup)
                && app.Environment.EnvironmentName != "Testing")
                db.Database.Migrate();
        }

        if (!app.Environment.IsDevelopment() && app.Environment.EnvironmentName != "Testing")
        {
            app.UseHsts();
            app.UseExceptionHandler();
        }

        app.UseSerilogRequestLogging(options =>
        {
            options.EnrichDiagnosticContext = (diagnosticContext, httpContext) =>
            {
                var traceId = Activity.Current?.Id;
                if (traceId != null)
                {
                    diagnosticContext.Set("TraceId", traceId);
                }

                if (httpContext.User.Identity is { IsAuthenticated: true })
                {
                    var claim = httpContext.User.Claims
                        .FirstOrDefault(c => c.Type == ClaimTypes.NameIdentifier);
                    if (claim != null)
                    {
                        diagnosticContext.Set("UserName", claim.Value);
                    }
                }
            };
        });

        // Serve SPA static files in production (from wwwroot/).
        // UseDefaultFiles is intentionally NOT used — we want requests for "/"
        // to fall through to the SPA fallback handler in Routes.cs, which
        // reads index.html and substitutes the __BASE_PATH__ placeholder
        // before serving. UseStaticFiles still handles assets, favicon, etc.
        if (!app.Environment.IsDevelopment())
        {
            app.UseStaticFiles();
        }

        app.UseCors();

        app.UseMiddleware<LogTraceIdMiddleware>();
        app.UseAuthentication();
        app.UseMiddleware<LogUserNameMiddleware>();
        app.UseAuthorization();

        if (app.Environment.IsDevelopment())
        {
            app.MapOpenApi();
            app.MapScalarApiReference();
        }
    }

    /// <summary>
    /// Emit a startup warning when an operator has explicitly configured
    /// <c>AllowedOrigins</c> but it doesn't intersect the actual listen URLs.
    /// In that state, every cookie-authenticated state-changing request from
    /// the SPA will be rejected by <c>OriginValidationFilter</c>, with no
    /// signal in the SPA beyond a generic "request failed" toast. One log
    /// line at startup turns that silent breakage into a noticeable one.
    ///
    /// Only fires when AllowedOrigins is explicitly configured — when it
    /// isn't, <see cref="AuthConstants.ResolveAllowedOrigins"/> already
    /// unions the listen URLs in, so there's nothing to warn about.
    /// </summary>
    private static void WarnOnAllowedOriginsMismatch(WebApplication app)
    {
        var configured = app.Configuration.GetValue<string>("AllowedOrigins");
        if (string.IsNullOrEmpty(configured)) return;

        var listenOrigins = AuthConstants.ResolveListenOrigins(app.Configuration);
        if (listenOrigins.Count == 0) return;

        var allowed = configured
            .Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .ToList();

        var intersects = allowed.Any(a => listenOrigins.Any(l =>
            string.Equals(a, l, StringComparison.OrdinalIgnoreCase)));
        if (intersects) return;

        var logger = app.Services.GetRequiredService<ILoggerFactory>().CreateLogger("PsTotp.Startup");
        LogAllowedOriginsMismatch(logger, string.Join(", ", allowed), string.Join(", ", listenOrigins));
    }
}
