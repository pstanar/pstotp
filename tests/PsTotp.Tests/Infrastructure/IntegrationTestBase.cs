using System.IdentityModel.Tokens.Jwt;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Configuration;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.IdentityModel.Tokens;
using PsTotp.Server.Infrastructure.Data;

namespace PsTotp.Tests.Infrastructure;

[TestClass]
public abstract class IntegrationTestBase
{
    private WebApplicationFactory<Program> _factory = null!;
    private SqliteConnection _connection = null!;

    protected HttpClient Client { get; private set; } = null!;

    protected static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
    };

    [TestInitialize]
    public void TestSetUp()
    {
        _connection = new SqliteConnection("DataSource=:memory:");
        _connection.Open();

        _factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(builder =>
            {
                builder.UseEnvironment("Testing");

                builder.ConfigureAppConfiguration((_, config) =>
                {
                    var settings = new Dictionary<string, string?>
                    {
                        ["DatabaseProvider"] = "PostgreSQL",
                        ["ConnectionStrings:PsTotpDb"] = "Host=dummy",
                        ["Jwt:Secret"] = PsTotpWebApplicationFactory.TestJwtSecret,
                        ["Jwt:Issuer"] = "pstotp",
                        ["Jwt:Audience"] = "pstotp",
                        ["Fido2:ServerDomain"] = "localhost",
                        ["Fido2:Origins:0"] = "http://localhost",
                        ["Serilog:MinimumLevel:Default"] = "Fatal",
                    };
                    foreach (var kv in GetAdditionalConfig())
                        settings[kv.Key] = kv.Value;
                    config.AddInMemoryCollection(settings);
                });

                builder.ConfigureTestServices(services =>
                {
                    // Replace database with SQLite
                    services.RemoveAll<AppDbContext>();
                    services.RemoveAll<DbContextOptions<AppDbContext>>();
                    services.RemoveAll<DbContextOptions>();

                    var dbOptions = new DbContextOptionsBuilder<AppDbContext>()
                        .UseSqlite(_connection)
                        .Options;

                    services.AddSingleton(dbOptions);
                    services.AddScoped<AppDbContext>();

                    // Override JWT validation to use our test secret
                    var testKey = new SymmetricSecurityKey(
                        Convert.FromBase64String(PsTotpWebApplicationFactory.TestJwtSecret));
                    services.PostConfigure<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme, opt =>
                    {
                        opt.TokenValidationParameters.IssuerSigningKey = testKey;
                    });
                });
            });

        // Create schema
        using var scope = _factory.Services.CreateScope();
        scope.ServiceProvider.GetRequiredService<AppDbContext>().Database.EnsureCreated();

        Client = _factory.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false,
        });
    }

    [TestCleanup]
    public void TestTearDown()
    {
        Client.Dispose();
        _factory.Dispose();
        _connection.Dispose();
    }

    protected virtual Dictionary<string, string?> GetAdditionalConfig() => new();

    protected (IServiceScope scope, AppDbContext db) GetDbContext()
    {
        var scope = _factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        return (scope, db);
    }

    protected HttpClient CreateAuthenticatedClient(Guid userId, string email, Guid deviceId, string? role = null)
    {
        var token = GenerateTestJwt(userId, email, deviceId, role);
        var client = _factory.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false,
        });
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return client;
    }

    protected async Task<(RegisterResult result, HttpClient client)> RegisterTestUserAsync(string? email = null)
    {
        email ??= $"test-{Guid.NewGuid():N}@example.com";
        var request = TestDataHelper.CreateRegisterRequest(email);

        var response = await Client.PostAsJsonAsync("/api/auth/register", request);
        response.EnsureSuccessStatusCode();

        var json = await response.Content.ReadFromJsonAsync<RegisterResult>(JsonOptions);
        Assert.IsNotNull(json);

        Assert.IsFalse(string.IsNullOrEmpty(json.AccessToken), "Register should return AccessToken for mobile client");

        var client = _factory.CreateClient(new WebApplicationFactoryClientOptions
        {
            AllowAutoRedirect = false,
        });
        client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", json.AccessToken);

        return (json, client);
    }

    protected async Task<LoginResult> LoginTestUserAsync(string email, string? deviceName = null, string? devicePublicKey = null)
    {
        var loginRequest = TestDataHelper.CreateLoginRequest(email, deviceName, devicePublicKey);
        var challengeResponse = await Client.PostAsJsonAsync("/api/auth/login", loginRequest);
        challengeResponse.EnsureSuccessStatusCode();

        var challenge = await challengeResponse.Content.ReadFromJsonAsync<LoginChallengeResult>(JsonOptions);
        Assert.IsNotNull(challenge);

        var nonce = Convert.FromBase64String(challenge.Challenge.Nonce);
        var proof = TestDataHelper.ComputeClientProof(nonce, Guid.Parse(challenge.LoginSessionId));

        var completeRequest = new { loginSessionId = challenge.LoginSessionId, clientProof = proof };
        var completeResponse = await Client.PostAsJsonAsync("/api/auth/login/complete", completeRequest);
        completeResponse.EnsureSuccessStatusCode();

        var result = await completeResponse.Content.ReadFromJsonAsync<LoginResult>(JsonOptions);
        Assert.IsNotNull(result);

        return result;
    }

    private static string GenerateTestJwt(Guid userId, string email, Guid deviceId, string? role = null)
    {
        var key = new SymmetricSecurityKey(
            Convert.FromBase64String(PsTotpWebApplicationFactory.TestJwtSecret));
        var credentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, userId.ToString()),
            new(JwtRegisteredClaimNames.Email, email),
            new("device_id", deviceId.ToString()),
            new(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
        };

        if (!string.IsNullOrEmpty(role))
            claims.Add(new Claim(ClaimTypes.Role, role));

        var token = new JwtSecurityToken(
            issuer: "pstotp",
            audience: "pstotp",
            claims: claims,
            expires: DateTime.UtcNow.AddMinutes(15),
            signingCredentials: credentials);

        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    // --- Result DTOs ---

    protected sealed record RegisterResult(string UserId, string DeviceId, string? AccessToken, string? RefreshToken);
    protected sealed record LoginChallengeResult(string LoginSessionId, LoginChallengeData Challenge);
    protected sealed record LoginChallengeData(string Nonce, KdfData Kdf);
    protected sealed record KdfData(string Algorithm, int MemoryMb, int Iterations, int Parallelism, string Salt);
    protected sealed record LoginResult(string? AccessToken, string? RefreshToken, LoginDeviceData Device, LoginEnvelopesData? Envelopes, string? ApprovalRequestId);
    protected sealed record LoginDeviceData(string DeviceId, string Status, bool PersistentKeyAllowed);
    protected sealed record LoginEnvelopesData(EnvelopeData? Password, EnvelopeData? Device);
    protected sealed record EnvelopeData(string Ciphertext, string Nonce, int Version);
}
