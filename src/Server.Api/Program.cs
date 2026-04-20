using System.Diagnostics;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Hosting.Systemd;
using Microsoft.Extensions.Hosting.WindowsServices;
using PsTotp.Server.Api;
using PsTotp.Server.Infrastructure.Data;
using Serilog;

#if DEBUG
Serilog.Debugging.SelfLog.Enable(Console.Error);
#endif

// --migrate: apply pending migrations and exit. Intended as the explicit
// step in a production deployment pipeline for non-SQLite providers, where
// automatic migration is off by default. Strip the flag before handing args
// to the generic host — it isn't a config key.
var migrateAndExit = args.Contains("--migrate");
var hostArgs = args.Where(a => a != "--migrate").ToArray();

try
{
    var builder = AppBuilder.CreateBuilder(hostArgs);

    var app = builder.Build();

    // Startup banner — sanitize connection string to avoid leaking credentials
    var dataDir = DataDirectory.Resolve(app.Configuration);
    var dbProvider = app.Configuration["_Resolved:DatabaseProvider"] ?? "unknown";
    var dbConn = app.Configuration["_Resolved:ConnectionString"] ?? "";
    // Shutdown via UI: auto-enabled for zero-config SQLite standalone, opt-in via EnableShutdown otherwise
    var isZeroConfigStandalone = !app.Environment.IsDevelopment()
                                 && app.Environment.EnvironmentName != "Testing"
                                 && !WindowsServiceHelpers.IsWindowsService()
                                 && !SystemdHelpers.IsSystemdService()
                                 && dbProvider == "SQLite";
    var shutdownEnabled = app.Configuration.GetValue("EnableShutdown", isZeroConfigStandalone);
    app.Configuration["_Resolved:ShutdownEnabled"] = shutdownEnabled.ToString();
    app.Configuration["_Resolved:MultiUser"] = (dbProvider != "SQLite").ToString();
    Log.Information("PsTotp starting{Mode}", migrateAndExit ? " in migration mode" : "");
    Log.Information("Data directory: {DataDir}", dataDir);
    Log.Information("Database: {Provider} ({Target})", dbProvider, SanitizeConnectionString(dbProvider, dbConn));

    if (migrateAndExit)
    {
        using var scope = app.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        try
        {
            var pending = (await db.Database.GetPendingMigrationsAsync()).ToList();
            if (pending.Count == 0)
            {
                Log.Information("No pending migrations — database is up to date");
                return 0;
            }
            Log.Information("Applying {Count} pending migration(s): {Migrations}",
                pending.Count, string.Join(", ", pending));
            await db.Database.MigrateAsync();
            Log.Information("Migrations applied successfully");
            return 0;
        }
        catch (Exception ex)
        {
            Log.Error(ex, "Migration failed");
            return 1;
        }
    }

    App.Configure(app);
    Routes.MapRoutes(app);

    // Open browser in production SQLite mode
    if (!app.Environment.IsDevelopment()
        && app.Environment.EnvironmentName != "Testing"
        && !WindowsServiceHelpers.IsWindowsService()
        && !SystemdHelpers.IsSystemdService()
        && dbProvider == "SQLite"
        && app.Configuration.GetValue("OpenBrowser", true))
    {
        app.Lifetime.ApplicationStarted.Register(() =>
        {
            // Resolve the actual listening address
            var addresses = app.Urls;
            var url = addresses.FirstOrDefault(a => a.StartsWith("http://localhost", StringComparison.OrdinalIgnoreCase))
                      ?? addresses.FirstOrDefault(a => a.StartsWith("http://", StringComparison.OrdinalIgnoreCase))
                         ?.Replace("0.0.0.0", "localhost")
                         .Replace("[::]", "localhost")
                      ?? AuthConstants.DefaultProductionOrigin;

            Log.Information("Opening browser at {Url}", url);
            try
            {
                if (OperatingSystem.IsWindows())
                    Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
                else if (OperatingSystem.IsMacOS())
                    Process.Start("open", url);
                else
                    Process.Start("xdg-open", url);
            }
            catch
            {
                Log.Information("Open {Url} in your browser", url);
            }
        });
    }

    app.Run();
    return 0;
}
finally
{
    Log.CloseAndFlush();
}

static string SanitizeConnectionString(string provider, string connectionString)
{
    if (provider == "SQLite")
        return connectionString; // SQLite is just a file path, no credentials

    // Extract host/database, strip credentials
    try
    {
        var parts = connectionString.Split(';')
            .Select(p => p.Trim())
            .Where(p => !string.IsNullOrEmpty(p))
            .Select(p =>
            {
                var key = p.Split('=')[0].Trim().ToLowerInvariant();
                return key is "password" or "pwd" or "user id" or "uid" or "username" ? null : p;
            })
            .Where(p => p != null);
        return string.Join("; ", parts);
    }
    catch
    {
        return "(connection configured)";
    }
}
