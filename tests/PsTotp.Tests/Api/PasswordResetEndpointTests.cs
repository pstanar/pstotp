using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using PsTotp.Tests.Infrastructure;

namespace PsTotp.Tests.Api;

[TestClass]
public class PasswordResetEndpointTests : IntegrationTestBase
{
    [TestMethod]
    public async Task BeginPasswordReset_Returns_Session_And_Code()
    {
        var email = $"reset-{Guid.NewGuid():N}@example.com";
        await RegisterTestUserAsync(email);

        var response = await Client.PostAsJsonAsync("/api/auth/password/reset/begin", new { email });
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);

        var json = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.IsTrue(json.TryGetProperty("resetSessionId", out _));
        Assert.IsTrue(json.TryGetProperty("verificationCode", out var code));
        Assert.IsFalse(string.IsNullOrEmpty(code.GetString()));
    }

    [TestMethod]
    public async Task BeginPasswordReset_Enumeration_Resistant()
    {
        // Unknown email should still return success shape
        var response = await Client.PostAsJsonAsync("/api/auth/password/reset/begin",
            new { email = "nonexistent@example.com" });
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);

        var json = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.IsTrue(json.TryGetProperty("resetSessionId", out _));
    }

    [TestMethod]
    public async Task VerifyCode_Returns_KdfConfig()
    {
        var email = $"reset-{Guid.NewGuid():N}@example.com";
        await RegisterTestUserAsync(email);

        var beginResp = await Client.PostAsJsonAsync("/api/auth/password/reset/begin", new { email });
        var beginJson = await beginResp.Content.ReadFromJsonAsync<JsonElement>();
        var sessionId = beginJson.GetProperty("resetSessionId").GetString();
        var code = beginJson.GetProperty("verificationCode").GetString();

        var verifyResp = await Client.PostAsJsonAsync("/api/auth/password/reset/verify",
            new { resetSessionId = sessionId, verificationCode = code });
        Assert.AreEqual(HttpStatusCode.OK, verifyResp.StatusCode);

        var verifyJson = await verifyResp.Content.ReadFromJsonAsync<JsonElement>();
        Assert.IsTrue(verifyJson.GetProperty("verified").GetBoolean());
        Assert.IsTrue(verifyJson.TryGetProperty("kdf", out _));
    }

    [TestMethod]
    public async Task VerifyCode_Rejects_Wrong_Code()
    {
        var email = $"reset-{Guid.NewGuid():N}@example.com";
        await RegisterTestUserAsync(email);

        var beginResp = await Client.PostAsJsonAsync("/api/auth/password/reset/begin", new { email });
        var beginJson = await beginResp.Content.ReadFromJsonAsync<JsonElement>();
        var sessionId = beginJson.GetProperty("resetSessionId").GetString();

        var verifyResp = await Client.PostAsJsonAsync("/api/auth/password/reset/verify",
            new { resetSessionId = sessionId, verificationCode = "000000" });
        Assert.AreEqual(HttpStatusCode.BadRequest, verifyResp.StatusCode);
    }

    [TestMethod]
    public async Task CompleteReset_Updates_Password()
    {
        var email = $"reset-{Guid.NewGuid():N}@example.com";
        await RegisterTestUserAsync(email);

        // Begin + verify
        var beginResp = await Client.PostAsJsonAsync("/api/auth/password/reset/begin", new { email });
        var beginJson = await beginResp.Content.ReadFromJsonAsync<JsonElement>();
        var sessionId = beginJson.GetProperty("resetSessionId").GetString();
        var code = beginJson.GetProperty("verificationCode").GetString();

        await Client.PostAsJsonAsync("/api/auth/password/reset/verify",
            new { resetSessionId = sessionId, verificationCode = code });

        // Complete with new verifier
        var dummyNonce = Convert.ToBase64String(new byte[12]);
        var dummyCiphertext = Convert.ToBase64String(new byte[48]);
        var completeResp = await Client.PostAsJsonAsync("/api/auth/password/reset/complete", new
        {
            resetSessionId = sessionId,
            newVerifier = new
            {
                verifier = TestDataHelper.NewTestVerifierBase64,
                kdf = new { algorithm = "argon2id", memoryMb = 64, iterations = 3, parallelism = 4, salt = TestDataHelper.TestSaltBase64 },
            },
            newPasswordEnvelope = new { ciphertext = dummyCiphertext, nonce = dummyNonce, version = 1 },
        });
        Assert.AreEqual(HttpStatusCode.OK, completeResp.StatusCode);

        var result = await completeResp.Content.ReadFromJsonAsync<JsonElement>();
        Assert.IsTrue(result.TryGetProperty("device", out _));
    }

    [TestMethod]
    public async Task CompleteReset_Rejects_Unverified_Session()
    {
        var email = $"reset-{Guid.NewGuid():N}@example.com";
        await RegisterTestUserAsync(email);

        var beginResp = await Client.PostAsJsonAsync("/api/auth/password/reset/begin", new { email });
        var beginJson = await beginResp.Content.ReadFromJsonAsync<JsonElement>();
        var sessionId = beginJson.GetProperty("resetSessionId").GetString();

        // Try to complete without verifying code
        var dummyNonce = Convert.ToBase64String(new byte[12]);
        var dummyCiphertext = Convert.ToBase64String(new byte[48]);
        var completeResp = await Client.PostAsJsonAsync("/api/auth/password/reset/complete", new
        {
            resetSessionId = sessionId,
            newVerifier = new
            {
                verifier = TestDataHelper.NewTestVerifierBase64,
                kdf = new { algorithm = "argon2id", memoryMb = 64, iterations = 3, parallelism = 4, salt = TestDataHelper.TestSaltBase64 },
            },
            newPasswordEnvelope = new { ciphertext = dummyCiphertext, nonce = dummyNonce, version = 1 },
        });
        Assert.AreEqual(HttpStatusCode.BadRequest, completeResp.StatusCode);
    }

    public TestContext TestContext { get; set; } = null!;
}
