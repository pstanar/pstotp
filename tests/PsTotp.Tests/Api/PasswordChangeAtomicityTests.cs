using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using Microsoft.EntityFrameworkCore;
using PsTotp.Server.Domain.Entities;
using PsTotp.Tests.Infrastructure;

namespace PsTotp.Tests.Api;

[TestClass]
public class PasswordChangeAtomicityTests : IntegrationTestBase
{
    [TestMethod]
    public async Task Password_Change_Updates_Verifier_And_Envelope_Atomically()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        var (_, authClient) = await RegisterTestUserAsync(email);

        // Step-up: get login challenge to prove current password
        var challengeResponse = await Client.PostAsJsonAsync("/api/auth/login",
            TestDataHelper.CreateLoginRequest(email), cancellationToken: TestContext.CancellationToken);
        var challenge = await challengeResponse.Content.ReadFromJsonAsync<LoginChallengeResult>(JsonOptions, TestContext.CancellationToken);
        Assert.IsNotNull(challenge);

        var nonce = Convert.FromBase64String(challenge.Challenge.Nonce);
        var currentProof = TestDataHelper.ComputeClientProof(nonce, Guid.Parse(challenge.LoginSessionId));

        var dummyNonce = Convert.ToBase64String(RandomNumberGenerator.GetBytes(12));
        var dummyCiphertext = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48));

        var response = await authClient.PostAsJsonAsync("/api/account/password/change", new
        {
            currentProof = new { loginSessionId = challenge.LoginSessionId, clientProof = currentProof },
            newVerifier = new
            {
                verifier = TestDataHelper.NewTestVerifierBase64,
                kdf = new { algorithm = "argon2id", memoryMb = 64, iterations = 3, parallelism = 4, salt = TestDataHelper.TestSaltBase64 },
            },
            newPasswordEnvelope = new { ciphertext = dummyCiphertext, nonce = dummyNonce, version = 1 },
        }, cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);

        // Old verifier should fail
        var c2Resp = await Client.PostAsJsonAsync("/api/auth/login", TestDataHelper.CreateLoginRequest(email), cancellationToken: TestContext.CancellationToken);
        var c2 = await c2Resp.Content.ReadFromJsonAsync<LoginChallengeResult>(JsonOptions, TestContext.CancellationToken);
        var oldProof = TestDataHelper.ComputeClientProof(
            Convert.FromBase64String(c2!.Challenge.Nonce), Guid.Parse(c2.LoginSessionId));
        var loginOld = await Client.PostAsJsonAsync("/api/auth/login/complete", new
        {
            loginSessionId = c2.LoginSessionId, clientProof = oldProof,
        }, cancellationToken: TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.Unauthorized, loginOld.StatusCode);

        // New verifier should succeed
        var c3Resp = await Client.PostAsJsonAsync("/api/auth/login", TestDataHelper.CreateLoginRequest(email), cancellationToken: TestContext.CancellationToken);
        var c3 = await c3Resp.Content.ReadFromJsonAsync<LoginChallengeResult>(JsonOptions, TestContext.CancellationToken);
        var newProof = TestDataHelper.ComputeClientProofWith(
            TestDataHelper.NewTestVerifier,
            Convert.FromBase64String(c3!.Challenge.Nonce), Guid.Parse(c3.LoginSessionId));
        var loginNew = await Client.PostAsJsonAsync("/api/auth/login/complete", new
        {
            loginSessionId = c3.LoginSessionId, clientProof = newProof,
        }, cancellationToken: TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.OK, loginNew.StatusCode);

        // DB: old envelope revoked, new one active
        var (scope, db) = GetDbContext();
        using (scope)
        {
            var user = await db.Users.FirstAsync(u => u.Email == email, TestContext.CancellationToken);
            var envelopes = await db.VaultKeyEnvelopes
                .Where(e => e.UserId == user.Id && e.EnvelopeType == EnvelopeType.Password)
                .ToListAsync(TestContext.CancellationToken);
            Assert.IsTrue(envelopes.Any(e => e.RevokedAt != null));
            Assert.IsTrue(envelopes.Any(e => e.RevokedAt == null));
        }
    }

    [TestMethod]
    public async Task Password_Change_Revokes_All_Sessions()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        var (_, authClient) = await RegisterTestUserAsync(email);

        // Login to get refresh token
        var loginResult = await LoginTestUserAsync(email);
        Assert.IsNotNull(loginResult.RefreshToken);

        // Step-up
        var cResp = await Client.PostAsJsonAsync("/api/auth/login", TestDataHelper.CreateLoginRequest(email), cancellationToken: TestContext.CancellationToken);
        var c = await cResp.Content.ReadFromJsonAsync<LoginChallengeResult>(JsonOptions, TestContext.CancellationToken);
        var proof = TestDataHelper.ComputeClientProof(
            Convert.FromBase64String(c!.Challenge.Nonce), Guid.Parse(c.LoginSessionId));

        var dummyNonce = Convert.ToBase64String(RandomNumberGenerator.GetBytes(12));
        var dummyCiphertext = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48));

        await authClient.PostAsJsonAsync("/api/account/password/change", new
        {
            currentProof = new { loginSessionId = c.LoginSessionId, clientProof = proof },
            newVerifier = new
            {
                verifier = TestDataHelper.NewTestVerifierBase64,
                kdf = new { algorithm = "argon2id", memoryMb = 64, iterations = 3, parallelism = 4, salt = TestDataHelper.TestSaltBase64 },
            },
            newPasswordEnvelope = new { ciphertext = dummyCiphertext, nonce = dummyNonce, version = 1 },
        }, cancellationToken: TestContext.CancellationToken);

        // Old refresh token should be revoked
        var refreshResponse = await Client.PostAsJsonAsync("/api/auth/refresh", new
        {
            refreshToken = loginResult.RefreshToken,
        }, cancellationToken: TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.Unauthorized, refreshResponse.StatusCode);
    }

    public TestContext TestContext { get; set; } = null!;
}
