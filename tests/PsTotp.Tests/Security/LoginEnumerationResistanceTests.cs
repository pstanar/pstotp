using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text.Json;
using PsTotp.Tests.Infrastructure;

namespace PsTotp.Tests.Security;

[TestClass]
public class LoginEnumerationResistanceTests : IntegrationTestBase
{
    [TestMethod]
    public async Task Login_With_Unknown_Email_Returns_Same_Shape_As_Known_Email()
    {
        var knownEmail = $"test-{Guid.NewGuid():N}@example.com";
        await Client.PostAsJsonAsync("/api/auth/register", TestDataHelper.CreateRegisterRequest(knownEmail), cancellationToken: TestContext.CancellationToken);

        var unknownEmail = $"unknown-{Guid.NewGuid():N}@example.com";

        var knownResponse = await Client.PostAsJsonAsync("/api/auth/login",
            TestDataHelper.CreateLoginRequest(knownEmail), cancellationToken: TestContext.CancellationToken);
        var unknownResponse = await Client.PostAsJsonAsync("/api/auth/login",
            TestDataHelper.CreateLoginRequest(unknownEmail), cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.OK, knownResponse.StatusCode);
        Assert.AreEqual(HttpStatusCode.OK, unknownResponse.StatusCode);

        var knownJson = await knownResponse.Content.ReadFromJsonAsync<JsonElement>(TestContext.CancellationToken);
        var unknownJson = await unknownResponse.Content.ReadFromJsonAsync<JsonElement>(TestContext.CancellationToken);

        Assert.IsTrue(knownJson.TryGetProperty("loginSessionId", out _));
        Assert.IsTrue(unknownJson.TryGetProperty("loginSessionId", out _));
        Assert.IsTrue(knownJson.TryGetProperty("challenge", out _));
        Assert.IsTrue(unknownJson.TryGetProperty("challenge", out _));
    }

    [TestMethod]
    public async Task Login_With_Unknown_Email_Returns_Plausible_Kdf_Parameters()
    {
        var unknownEmail = $"unknown-{Guid.NewGuid():N}@example.com";

        var response = await Client.PostAsJsonAsync("/api/auth/login",
            TestDataHelper.CreateLoginRequest(unknownEmail), cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);

        var result = await response.Content.ReadFromJsonAsync<LoginChallengeResult>(JsonOptions, TestContext.CancellationToken);
        Assert.IsNotNull(result);
        Assert.AreEqual("argon2id", result.Challenge.Kdf.Algorithm);
        Assert.AreEqual(64, result.Challenge.Kdf.MemoryMb);
        Assert.AreEqual(3, result.Challenge.Kdf.Iterations);
        Assert.AreEqual(4, result.Challenge.Kdf.Parallelism);
        Assert.IsFalse(string.IsNullOrEmpty(result.Challenge.Kdf.Salt));
    }

    [TestMethod]
    public async Task Login_Complete_With_Invalid_Proof_Returns_401()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        await Client.PostAsJsonAsync("/api/auth/register", TestDataHelper.CreateRegisterRequest(email), cancellationToken: TestContext.CancellationToken);

        var challengeResponse = await Client.PostAsJsonAsync("/api/auth/login",
            TestDataHelper.CreateLoginRequest(email), cancellationToken: TestContext.CancellationToken);
        var challenge = await challengeResponse.Content.ReadFromJsonAsync<LoginChallengeResult>(JsonOptions, TestContext.CancellationToken);

        var wrongProof = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32));
        var response = await Client.PostAsJsonAsync("/api/auth/login/complete", new
        {
            loginSessionId = challenge!.LoginSessionId,
            clientProof = wrongProof,
        }, cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [TestMethod]
    public async Task Login_Rate_Limiting_Engages_After_Threshold()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        await Client.PostAsJsonAsync("/api/auth/register", TestDataHelper.CreateRegisterRequest(email));

        // 5 failed login attempts
        for (var i = 0; i < 5; i++)
        {
            var cResp = await Client.PostAsJsonAsync("/api/auth/login", TestDataHelper.CreateLoginRequest(email));
            var c = await cResp.Content.ReadFromJsonAsync<LoginChallengeResult>(JsonOptions);
            var wrongProof = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32));
            await Client.PostAsJsonAsync("/api/auth/login/complete", new
            {
                loginSessionId = c!.LoginSessionId,
                clientProof = wrongProof,
            });
        }

        // 6th attempt → 429
        var c6Resp = await Client.PostAsJsonAsync("/api/auth/login", TestDataHelper.CreateLoginRequest(email));
        var c6 = await c6Resp.Content.ReadFromJsonAsync<LoginChallengeResult>(JsonOptions);
        var wrongProof6 = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32));
        var response = await Client.PostAsJsonAsync("/api/auth/login/complete", new
        {
            loginSessionId = c6!.LoginSessionId,
            clientProof = wrongProof6,
        });

        Assert.AreEqual((HttpStatusCode)429, response.StatusCode);
    }

    [TestMethod]
    [Ignore("Requires precise timing measurement")]
    public async Task Login_Timing_Is_Indistinguishable_Between_Known_And_Unknown_Email()
    {
        await Task.CompletedTask;
    }

    public TestContext TestContext { get; set; } = null!;
}
