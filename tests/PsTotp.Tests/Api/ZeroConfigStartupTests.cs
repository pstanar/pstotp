using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using PsTotp.Server.Api;
using PsTotp.Server.Infrastructure.Data;

namespace PsTotp.Tests.Api;

[TestClass]
public class ZeroConfigStartupTests
{
    private WebApplicationFactory<Program> _factory = null!;
    private HttpClient _client = null!;
    private SqliteConnection _connection = null!;

    [TestInitialize]
    public void TestSetUp()
    {
        _connection = new SqliteConnection("DataSource=:memory:");
        _connection.Open();

        _factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(builder =>
            {
                builder.UseEnvironment("Testing");

                // No Jwt:Secret, no DatabaseProvider, no Fido2 — all should auto-default
                builder.ConfigureAppConfiguration((_, config) =>
                {
                    config.AddInMemoryCollection(new Dictionary<string, string?>
                    {
                        ["Serilog:MinimumLevel:Default"] = "Fatal",
                    });
                });

                builder.ConfigureTestServices(services =>
                {
                    services.RemoveAll<AppDbContext>();
                    services.RemoveAll<DbContextOptions<AppDbContext>>();
                    services.RemoveAll<DbContextOptions>();

                    var dbOptions = new DbContextOptionsBuilder<AppDbContext>()
                        .UseSqlite(_connection)
                        .Options;

                    services.AddSingleton(dbOptions);
                    services.AddScoped<AppDbContext>();
                });
            });

        using var scope = _factory.Services.CreateScope();
        scope.ServiceProvider.GetRequiredService<AppDbContext>().Database.EnsureCreated();

        _client = _factory.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false,
        });
    }

    [TestCleanup]
    public void TestTearDown()
    {
        _client.Dispose();
        _factory.Dispose();
        _connection.Dispose();
    }

    [TestMethod]
    public async Task Health_Endpoint_Works_With_Zero_Config()
    {
        var response = await _client.GetAsync("/api/health");
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);
    }

    [TestMethod]
    public async Task Register_Returns_Verification_Code_Without_Email_Service()
    {
        var email = $"zero-config-{Guid.NewGuid():N}@example.com";
        var response = await _client.PostAsJsonAsync("/api/auth/register/begin", new { email });
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);

        var result = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.IsTrue(result.TryGetProperty("verificationCode", out var codeElement),
            "Verification code should be returned when no email service is configured");
        Assert.IsFalse(string.IsNullOrEmpty(codeElement.GetString()));
    }

    [TestMethod]
    public async Task Full_Registration_Flow_Works_With_Zero_Config()
    {
        var email = $"zero-config-{Guid.NewGuid():N}@example.com";

        // Begin registration
        var beginResp = await _client.PostAsJsonAsync("/api/auth/register/begin", new { email });
        Assert.AreEqual(HttpStatusCode.OK, beginResp.StatusCode);
        var beginResult = await beginResp.Content.ReadFromJsonAsync<JsonElement>();
        var sessionId = beginResult.GetProperty("registrationSessionId").GetString();
        var code = beginResult.GetProperty("verificationCode").GetString();

        // Verify email
        var verifyResp = await _client.PostAsJsonAsync("/api/auth/register/verify-email",
            new { registrationSessionId = sessionId, verificationCode = code });
        Assert.AreEqual(HttpStatusCode.OK, verifyResp.StatusCode);

        // Register
        var request = Infrastructure.TestDataHelper.CreateRegisterRequest(email);
        var registerResp = await _client.PostAsJsonAsync("/api/auth/register", request);
        Assert.AreEqual(HttpStatusCode.OK, registerResp.StatusCode);
    }

    [TestMethod]
    public void DataDirectory_Resolve_Uses_Config_Override()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"pstotp-test-{Guid.NewGuid():N}");
        try
        {
            var config = new ConfigurationBuilder()
                .AddInMemoryCollection(new Dictionary<string, string?> { ["DataDirectory"] = tempDir })
                .Build();

            var resolved = DataDirectory.Resolve(config);
            Assert.AreEqual(tempDir, resolved);
            Assert.IsTrue(Directory.Exists(tempDir));
        }
        finally
        {
            try { Directory.Delete(tempDir, true); } catch { /* best effort */ }
        }
    }

    [TestMethod]
    public void DataDirectory_Resolve_Returns_Platform_Default()
    {
        var resolved = DataDirectory.Resolve();
        Assert.IsFalse(string.IsNullOrEmpty(resolved));
        StringAssert.Contains(resolved, "pstotp");
    }

    public TestContext TestContext { get; set; } = null!;
}
