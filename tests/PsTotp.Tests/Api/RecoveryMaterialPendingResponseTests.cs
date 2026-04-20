using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using PsTotp.Tests.Infrastructure;

namespace PsTotp.Tests.Api;

[TestClass]
public class RecoveryMaterialPendingResponseTests : IntegrationTestBase
{
    // Use a 24-hour hold period (default) for the pending test,
    // and manipulate DB for the ready test
    protected override Dictionary<string, string?> GetAdditionalConfig() => new()
    {
        ["Recovery:HoldPeriodHours"] = "24",
    };

    [TestMethod]
    public async Task Recovery_Material_Returns_Pending_During_Hold_Period()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        await RegisterTestUserAsync(email);

        // Get a login session for step-up proof
        var challengeResp = await Client.PostAsJsonAsync("/api/auth/login",
            TestDataHelper.CreateLoginRequest(email));
        var challenge = await challengeResp.Content.ReadFromJsonAsync<LoginChallengeResult>(JsonOptions);
        var nonce = Convert.FromBase64String(challenge!.Challenge.Nonce);
        var proof = TestDataHelper.ComputeClientProof(nonce, Guid.Parse(challenge.LoginSessionId));

        // Redeem a recovery code
        var redeemResponse = await Client.PostAsJsonAsync("/api/recovery/codes/redeem", new
        {
            email,
            recoveryCode = TestDataHelper.TestRecoveryCodes[0],
            verifierProof = new { loginSessionId = challenge.LoginSessionId, clientProof = proof },
        });

        Assert.AreEqual(HttpStatusCode.OK, redeemResponse.StatusCode);
        var redeemResult = await redeemResponse.Content.ReadFromJsonAsync<JsonElement>();
        var sessionId = redeemResult.GetProperty("recoverySessionId").GetString();
        Assert.IsNotNull(sessionId);

        // Immediately request material → should be pending
        var materialResponse = await Client.PostAsJsonAsync($"/api/recovery/session/{sessionId}/material", new
        {
            replacementDevice = new { deviceName = "Recovery Device", platform = "test", clientType = "mobile", devicePublicKey = "" },
        });

        Assert.AreEqual(HttpStatusCode.OK, materialResponse.StatusCode);
        var material = await materialResponse.Content.ReadFromJsonAsync<JsonElement>();
        Assert.AreEqual("pending", material.GetProperty("status").GetString());
        Assert.IsTrue(material.TryGetProperty("releaseEarliestAt", out _));
    }

    [TestMethod]
    public async Task Recovery_Material_Returns_Ready_After_Hold_Period()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        await RegisterTestUserAsync(email);

        // Step-up
        var challengeResp = await Client.PostAsJsonAsync("/api/auth/login",
            TestDataHelper.CreateLoginRequest(email));
        var challenge = await challengeResp.Content.ReadFromJsonAsync<LoginChallengeResult>(JsonOptions);
        var nonce = Convert.FromBase64String(challenge!.Challenge.Nonce);
        var proof = TestDataHelper.ComputeClientProof(nonce, Guid.Parse(challenge.LoginSessionId));

        // Redeem
        var redeemResponse = await Client.PostAsJsonAsync("/api/recovery/codes/redeem", new
        {
            email,
            recoveryCode = TestDataHelper.TestRecoveryCodes[0],
            verifierProof = new { loginSessionId = challenge.LoginSessionId, clientProof = proof },
        });
        var redeemResult = await redeemResponse.Content.ReadFromJsonAsync<JsonElement>();
        var sessionId = redeemResult.GetProperty("recoverySessionId").GetString();

        // Manipulate DB to set hold period to past
        {
            var (scope, db) = GetDbContext();
            using (scope)
            {
                var session = await db.RecoverySessions.FirstAsync(s => s.Id == Guid.Parse(sessionId!));
                session.ReleaseEarliestAt = DateTime.UtcNow.AddMinutes(-1);
                await db.SaveChangesAsync();
            }
        }

        // Request material → should be ready
        var materialResponse = await Client.PostAsJsonAsync($"/api/recovery/session/{sessionId}/material", new
        {
            replacementDevice = new { deviceName = "Recovery Device", platform = "test", clientType = "mobile", devicePublicKey = "some-key" },
        });

        Assert.AreEqual(HttpStatusCode.OK, materialResponse.StatusCode);
        var material = await materialResponse.Content.ReadFromJsonAsync<JsonElement>();
        Assert.AreEqual("ready", material.GetProperty("status").GetString());
        Assert.IsTrue(material.TryGetProperty("replacementDeviceId", out var rid));
        Assert.IsFalse(string.IsNullOrEmpty(rid.GetString()));
    }

    public TestContext TestContext { get; set; } = null!;
}
