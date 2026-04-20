using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using PsTotp.Server.Infrastructure.Data;

namespace PsTotp.Tests.Infrastructure;

public class PsTotpWebApplicationFactory : WebApplicationFactory<Program>
{
    public const string TestJwtSecret = "dGVzdC1zZWNyZXQta2V5LWZvci1pbnRlZ3JhdGlvbi10ZXN0cw==";

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");

        builder.ConfigureAppConfiguration((_, config) =>
        {
            config.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["DatabaseProvider"] = "PostgreSQL",
                ["ConnectionStrings:PsTotpDb"] = "Host=dummy",
                ["Jwt:Secret"] = TestJwtSecret,
                ["Jwt:Issuer"] = "pstotp",
                ["Jwt:Audience"] = "pstotp",
                ["Serilog:MinimumLevel:Default"] = "Fatal",
            });
        });
    }

    public WebApplicationFactory<Program> CreateTestVariant(SqliteConnection connection)
    {
        return WithWebHostBuilder(builder =>
        {
            builder.ConfigureTestServices(services =>
            {
                // Remove everything related to AppDbContext
                services.RemoveAll<AppDbContext>();
                services.RemoveAll<DbContextOptions<AppDbContext>>();
                services.RemoveAll<DbContextOptions>();

                // Build fresh DbContextOptions with only SQLite
                var options = new DbContextOptionsBuilder<AppDbContext>()
                    .UseSqlite(connection)
                    .Options;

                // Register as singleton (connection is per-test, owned by test)
                services.AddSingleton(options);
                services.AddScoped<AppDbContext>();
            });
        });
    }
}
