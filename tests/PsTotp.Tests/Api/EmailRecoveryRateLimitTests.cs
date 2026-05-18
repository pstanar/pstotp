using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using PsTotp.Tests.Infrastructure;

namespace PsTotp.Tests.Api;

[TestClass]
public class EmailRecoveryRateLimitTests : IntegrationTestBase
{
    [TestMethod]
    public async Task Recovery_Code_Redemption_Rate_Limited_After_Three_Attempts()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        await RegisterTestUserAsync(email);

        // Submit 3 invalid recovery codes (need fresh login sessions for each)
        for (var i = 0; i < 3; i++)
        {
            var cResp = await Client.PostAsJsonAsync("/api/auth/login", TestDataHelper.CreateLoginRequest(email));
            var c = await cResp.Content.ReadFromJsonAsync<LoginChallengeResult>(JsonOptions);
            var proof = TestDataHelper.ComputeClientProof(
                Convert.FromBase64String(c!.Challenge.Nonce), Guid.Parse(c.LoginSessionId));

            await Client.PostAsJsonAsync("/api/recovery/codes/redeem", new
            {
                email,
                recoveryCode = "INVALIDCODE",
                verifierProof = new { loginSessionId = c.LoginSessionId, clientProof = proof },
            });
        }

        // 4th attempt should be rate limited
        var cResp4 = await Client.PostAsJsonAsync("/api/auth/login", TestDataHelper.CreateLoginRequest(email));
        var c4 = await cResp4.Content.ReadFromJsonAsync<LoginChallengeResult>(JsonOptions);
        var proof4 = TestDataHelper.ComputeClientProof(
            Convert.FromBase64String(c4!.Challenge.Nonce), Guid.Parse(c4.LoginSessionId));

        var response = await Client.PostAsJsonAsync("/api/recovery/codes/redeem", new
        {
            email,
            recoveryCode = "INVALIDCODE",
            verifierProof = new { loginSessionId = c4.LoginSessionId, clientProof = proof4 },
        });

        Assert.AreEqual((HttpStatusCode)429, response.StatusCode);
    }

    [TestMethod]
    public async Task Login_Rate_Limited_After_Five_Failed_Attempts()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        await RegisterTestUserAsync(email);

        // Submit 5 failed login proofs
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

        // 6th attempt should be rate limited
        var cResp6 = await Client.PostAsJsonAsync("/api/auth/login", TestDataHelper.CreateLoginRequest(email));
        var c6 = await cResp6.Content.ReadFromJsonAsync<LoginChallengeResult>(JsonOptions);

        var wrongProof6 = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32));
        var response = await Client.PostAsJsonAsync("/api/auth/login/complete", new
        {
            loginSessionId = c6!.LoginSessionId,
            clientProof = wrongProof6,
        });

        Assert.AreEqual((HttpStatusCode)429, response.StatusCode);
    }

    [TestMethod]
    public async Task Registration_Rate_Limited_By_IP_After_Five_Distinct_Emails()
    {
        // Five attempts from the same client IP using DIFFERENT emails each
        // time (so the per-email session limit can't fire). The IP-keyed
        // backstop should kick in on the sixth.
        for (var i = 0; i < 5; i++)
        {
            var response = await Client.PostAsJsonAsync(
                "/api/auth/register/begin",
                new { email = $"spam-{Guid.NewGuid():N}@example.com" });
            Assert.AreNotEqual((HttpStatusCode)429, response.StatusCode,
                $"attempt #{i + 1} should still be allowed");
        }

        var sixth = await Client.PostAsJsonAsync(
            "/api/auth/register/begin",
            new { email = $"spam-{Guid.NewGuid():N}@example.com" });
        Assert.AreEqual((HttpStatusCode)429, sixth.StatusCode);
    }

    [TestMethod]
    public async Task Password_Reset_Begin_Rate_Limited_By_IP_After_Five_Distinct_Emails()
    {
        // Same shape as the registration test — different bucket, same
        // budget (5 per IP per hour).
        for (var i = 0; i < 5; i++)
        {
            var response = await Client.PostAsJsonAsync(
                "/api/auth/password/reset/begin",
                new { email = $"spam-{Guid.NewGuid():N}@example.com" });
            Assert.AreNotEqual((HttpStatusCode)429, response.StatusCode,
                $"attempt #{i + 1} should still be allowed");
        }

        var sixth = await Client.PostAsJsonAsync(
            "/api/auth/password/reset/begin",
            new { email = $"spam-{Guid.NewGuid():N}@example.com" });
        Assert.AreEqual((HttpStatusCode)429, sixth.StatusCode);
    }

    public TestContext TestContext { get; set; } = null!;
}
