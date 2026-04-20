using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration.Json;
using Microsoft.IdentityModel.Tokens;
using PsTotp.Server.Infrastructure;
using PsTotp.Server.Infrastructure.Data;
using Serilog;

namespace PsTotp.Server.Api;

public static class AppBuilder
{
    private const string ConfigFileKey = "ConfigFile";
    private const string PsTotpConfigFileKey = "PsTotpConfigFile";

    public static WebApplicationBuilder CreateBuilder(string[] args)
    {
        var builder = WebApplication.CreateBuilder(args);
        builder.Host.UseWindowsService();
        builder.Host.UseSystemd();

        AddExternalConfigFile(builder.Configuration);

        // Resolve data directory early — needed by JWT, DB, and logging
        var dataDir = DataDirectory.Resolve(builder.Configuration);

        ConfigureListenUrl(builder, dataDir);
        ConfigureLogging(builder, dataDir);
        ConfigureServices(builder, dataDir);

        return builder;
    }

    private static void AddExternalConfigFile(ConfigurationManager configuration)
    {
        var configFile = configuration[ConfigFileKey] ?? configuration[PsTotpConfigFileKey];
        if (string.IsNullOrEmpty(configFile))
            return;

        var insertIndex = FindLastJsonSourceIndex(configuration) + 1;
        var source = new JsonConfigurationSource
        {
            Path = configFile,
            Optional = true,
            ReloadOnChange = false,
        };
        source.ResolveFileProvider();
        configuration.Sources.Insert(insertIndex, source);
    }

    private static int FindLastJsonSourceIndex(ConfigurationManager configuration)
    {
        for (var i = configuration.Sources.Count - 1; i >= 0; i--)
        {
            if (configuration.Sources[i] is JsonConfigurationSource)
                return i;
        }
        return -1;
    }

    private static void ConfigureListenUrl(WebApplicationBuilder builder, string dataDir)
    {
        // Only set default URL if no explicit config is present
        var hasExplicitUrls = Environment.GetEnvironmentVariable("ASPNETCORE_URLS") != null
            || builder.Configuration.GetSection("Kestrel:Endpoints").Exists()
            || ArgsContainUrls();

        if (hasExplicitUrls)
            return;

        if (builder.Environment.IsDevelopment() || builder.Environment.EnvironmentName == "Testing")
            return;

        var enableHttps = builder.Configuration.GetValue("EnableHttps", false);
        if (enableHttps)
        {
            // Serve on HTTP + HTTPS with self-signed cert for LAN access
            var cert = DevCertificate.GetOrCreate(dataDir);
            builder.WebHost.ConfigureKestrel(kestrel =>
            {
                kestrel.ListenAnyIP(5000); // HTTP
                kestrel.ListenAnyIP(5001, listenOptions => listenOptions.UseHttps(cert)); // HTTPS
            });
        }
        else
        {
            // HTTP only — for use behind a reverse proxy that handles TLS
            builder.WebHost.UseUrls(AuthConstants.DefaultListenUrl);
        }

        return;

        static bool ArgsContainUrls()
        {
            var args = Environment.GetCommandLineArgs();
            return args.Any(a => a.StartsWith("--urls", StringComparison.OrdinalIgnoreCase));
        }
    }

    private static void ConfigureLogging(WebApplicationBuilder builder, string dataDir)
    {
        // Inject file sink config if no sinks are configured and not in dev/test
        if (!builder.Configuration.GetSection("Serilog:WriteTo").GetChildren().Any()
            && !builder.Environment.IsDevelopment()
            && builder.Environment.EnvironmentName != "Testing")
        {
            var logDir = Path.Combine(dataDir, "logs");
            Directory.CreateDirectory(logDir);
            var logPath = Path.Combine(logDir, "pstotp-.log");

            builder.Configuration.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Serilog:Using:5"] = "Serilog.Sinks.File",
                ["Serilog:WriteTo:0:Name"] = "File",
                ["Serilog:WriteTo:0:Args:path"] = logPath,
                ["Serilog:WriteTo:0:Args:rollingInterval"] = "Day",
                ["Serilog:WriteTo:0:Args:retainedFileCountLimit"] = "30",
                ["Serilog:WriteTo:0:Args:outputTemplate"] =
                    "{Timestamp:yyyy-MM-dd HH:mm:ss.fff zzz} [{Level:u3}] {Message:lj}{NewLine}{Exception}",
            });
        }

        builder.Services.AddSerilog((services, config) => config
            .ReadFrom.Configuration(builder.Configuration)
            .ReadFrom.Services(services)
        );
    }

    private static void ConfigureServices(WebApplicationBuilder builder, string dataDir)
    {
        builder.Services.AddOpenApi();
        builder.Services.AddProblemDetails();
        builder.Services.AddExceptionHandler<GlobalExceptionHandler>();

        builder.Services.ConfigureHttpJsonOptions(options =>
        {
            options.SerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
            options.SerializerOptions.DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull;
            options.SerializerOptions.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.CamelCase));
        });

        ConfigureAuthentication(builder, dataDir);
        ConfigureAuthorization(builder);

        ConfigureDatabase(builder, dataDir);
        builder.Services.AddInfrastructure(builder.Configuration);

        ConfigureCors(builder);
    }

    private static void ConfigureAuthentication(WebApplicationBuilder builder, string dataDir)
    {
        var jwtSecret = builder.Configuration["Jwt:Secret"];

        if (string.IsNullOrEmpty(jwtSecret))
        {
            jwtSecret = ResolveJwtSecret(dataDir);
            // Inject into config so TokenService and other consumers can read it
            builder.Configuration["Jwt:Secret"] = jwtSecret;
        }

        var key = new SymmetricSecurityKey(Convert.FromBase64String(jwtSecret));

        builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
            .AddJwtBearer(options =>
            {
                options.TokenValidationParameters = new TokenValidationParameters
                {
                    ValidateIssuer = true,
                    ValidateAudience = true,
                    ValidateLifetime = true,
                    ValidateIssuerSigningKey = true,
                    ValidIssuer = builder.Configuration["Jwt:Issuer"] ?? Application.SharedConstants.DefaultJwtIssuer,
                    ValidAudience = builder.Configuration["Jwt:Audience"] ?? Application.SharedConstants.DefaultJwtAudience,
                    IssuerSigningKey = key,
                    ClockSkew = TimeSpan.FromSeconds(30),
                };

                options.Events = new JwtBearerEvents
                {
                    OnMessageReceived = context =>
                    {
                        if (context.Request.Cookies.TryGetValue(AuthConstants.AccessTokenCookieName, out var cookie)
                            && !string.IsNullOrEmpty(cookie))
                        {
                            context.Token = cookie;
                        }
                        return Task.CompletedTask;
                    },
                };
            });
    }

    private static string ResolveJwtSecret(string dataDir)
    {
        var keyFile = Path.Combine(dataDir, "jwt-secret.key");

        if (File.Exists(keyFile))
        {
            var existing = File.ReadAllText(keyFile).Trim();
            if (!string.IsNullOrEmpty(existing))
                return existing;
        }

        var secretBytes = RandomNumberGenerator.GetBytes(32);
        var secret = Convert.ToBase64String(secretBytes);
        File.WriteAllText(keyFile, secret);
        Log.Information("Generated new JWT secret at {KeyFile}", keyFile);
        return secret;
    }

    private static void ConfigureDatabase(WebApplicationBuilder builder, string dataDir)
    {
        var provider = builder.Configuration.GetValue<string>("DatabaseProvider");
        var connectionString = builder.Configuration.GetConnectionString("PsTotpDb");

        // Auto-default to SQLite when nothing is configured
        if (string.IsNullOrEmpty(provider) && string.IsNullOrEmpty(connectionString))
        {
            provider = "SQLite";
            connectionString = $"Data Source={Path.Combine(dataDir, "pstotp.db")}";
        }

        provider ??= "PostgreSQL";

        if (provider == "SQLite" && string.IsNullOrEmpty(connectionString))
            connectionString = $"Data Source={Path.Combine(dataDir, "pstotp.db")}";

        if (string.IsNullOrEmpty(connectionString))
            throw new InvalidOperationException("ConnectionStrings:PsTotpDb must be configured.");

        // Store resolved values for startup banner
        builder.Configuration["_Resolved:DatabaseProvider"] = provider;
        builder.Configuration["_Resolved:ConnectionString"] = connectionString;

        builder.Services.AddDbContext<AppDbContext>(options =>
        {
            switch (provider)
            {
                case "PostgreSQL":
                    options.UseNpgsql(connectionString,
                        o => o.MigrationsAssembly("PsTotp.Server.Infrastructure.Postgres"));
                    break;
                case "SqlServer":
                    options.UseSqlServer(connectionString,
                        o => o.MigrationsAssembly("PsTotp.Server.Infrastructure.SqlServer"));
                    break;
                case "MySql":
                    options.UseMySQL(connectionString,
                        o => o.MigrationsAssembly("PsTotp.Server.Infrastructure.MySql"));
                    break;
                case "SQLite":
                    options.UseSqlite(connectionString,
                        o => o.MigrationsAssembly("PsTotp.Server.Infrastructure.Sqlite"));
                    break;
                default:
                    throw new InvalidOperationException(
                        $"Unsupported database provider: '{provider}'. Supported values: PostgreSQL, SqlServer, MySql, SQLite.");
            }
        });
    }

    private static void ConfigureCors(WebApplicationBuilder builder)
    {
        builder.Services.AddCors(options =>
        {
            options.AddDefaultPolicy(policy =>
            {
                var origins = AuthConstants.ResolveAllowedOrigins(builder.Configuration, builder.Environment.IsDevelopment());
                policy.WithOrigins(origins.Split(';'))
                    .AllowAnyHeader()
                    .AllowAnyMethod()
                    .AllowCredentials();
            });
        });
    }

    private static void ConfigureAuthorization(WebApplicationBuilder builder)
    {
        builder.Services.AddAuthorizationBuilder()
            .AddPolicy(AuthConstants.UserPolicy, policy => policy.RequireAuthenticatedUser())
            .AddPolicy(AuthConstants.AdminPolicy, policy => policy.RequireRole(Application.SharedConstants.AdminRole));
    }
}
