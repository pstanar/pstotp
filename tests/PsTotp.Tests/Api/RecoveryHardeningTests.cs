using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using PsTotp.Server.Domain.Entities;
using PsTotp.Tests.Infrastructure;

namespace PsTotp.Tests.Api;

[TestClass]
public class RecoveryHardeningTests : IntegrationTestBase
{
    protected override Dictionary<string, string?> GetAdditionalConfig() => new()
    {
        ["Recovery:HoldPeriodHours"] = "24",
    };

    // --- Recovery Code Regeneration ---

    [TestMethod]
    public async Task Regenerate_Recovery_Codes_Replaces_Old_Codes()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        var (result, authedClient) = await RegisterTestUserAsync(email);

        var dummyNonce = Convert.ToBase64String(RandomNumberGenerator.GetBytes(12));
        var dummyCiphertext = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48));

        // Generate new hashes (different from original)
        var newHashes = Enumerable.Range(0, 8)
            .Select(_ => Convert.ToBase64String(RandomNumberGenerator.GetBytes(32)))
            .ToList();

        var response = await authedClient.PostAsJsonAsync("/api/recovery/codes/regenerate", new
        {
            rotatedRecovery = new
            {
                recoveryEnvelopeCiphertext = dummyCiphertext,
                recoveryEnvelopeNonce = dummyNonce,
                recoveryEnvelopeVersion = 1,
                recoveryCodeHashes = newHashes,
            },
        });

        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);

        // Verify old codes are replaced and new codes exist
        var (scope, db) = GetDbContext();
        using (scope)
        {
            var userId = Guid.Parse(result.UserId);
            var activeCodes = await db.RecoveryCodes
                .Where(c => c.UserId == userId && c.ReplacedAt == null)
                .ToListAsync();
            Assert.HasCount(8, activeCodes);

            var replacedCodes = await db.RecoveryCodes
                .Where(c => c.UserId == userId && c.ReplacedAt != null)
                .ToListAsync();
            Assert.HasCount(8, replacedCodes);
        }
    }

    [TestMethod]
    public async Task Regenerate_Recovery_Codes_Rotates_Recovery_Envelope()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        var (result, authedClient) = await RegisterTestUserAsync(email);

        var dummyNonce = Convert.ToBase64String(RandomNumberGenerator.GetBytes(12));
        var dummyCiphertext = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48));
        var newHashes = Enumerable.Range(0, 8)
            .Select(_ => Convert.ToBase64String(RandomNumberGenerator.GetBytes(32)))
            .ToList();

        var response = await authedClient.PostAsJsonAsync("/api/recovery/codes/regenerate", new
        {
            rotatedRecovery = new
            {
                recoveryEnvelopeCiphertext = dummyCiphertext,
                recoveryEnvelopeNonce = dummyNonce,
                recoveryEnvelopeVersion = 1,
                recoveryCodeHashes = newHashes,
            },
        });

        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);

        var (scope, db) = GetDbContext();
        using (scope)
        {
            var userId = Guid.Parse(result.UserId);
            var activeEnvelopes = await db.VaultKeyEnvelopes
                .Where(e => e.UserId == userId && e.EnvelopeType == EnvelopeType.Recovery && e.RevokedAt == null)
                .ToListAsync();
            Assert.HasCount(1, activeEnvelopes);

            var revokedEnvelopes = await db.VaultKeyEnvelopes
                .Where(e => e.UserId == userId && e.EnvelopeType == EnvelopeType.Recovery && e.RevokedAt != null)
                .ToListAsync();
            Assert.HasCount(1, revokedEnvelopes);
        }
    }

    [TestMethod]
    public async Task Regenerate_Recovery_Codes_Requires_Approved_Device()
    {
        // Create an unauthenticated client with a fake JWT for a non-existent device
        var fakeClient = CreateAuthenticatedClient(Guid.NewGuid(), "fake@example.com", Guid.NewGuid());

        var response = await fakeClient.PostAsJsonAsync("/api/recovery/codes/regenerate", new
        {
            rotatedRecovery = new
            {
                recoveryEnvelopeCiphertext = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48)),
                recoveryEnvelopeNonce = Convert.ToBase64String(RandomNumberGenerator.GetBytes(12)),
                recoveryEnvelopeVersion = 1,
                recoveryCodeHashes = new[] { "hash1", "hash2" },
            },
        });

        Assert.AreEqual(HttpStatusCode.Forbidden, response.StatusCode);
        fakeClient.Dispose();
    }

    // --- Recovery Session Cancellation ---

    [TestMethod]
    public async Task Cancel_Recovery_Session_During_Hold_Period()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        var (_, authedClient) = await RegisterTestUserAsync(email);

        // Start a recovery session
        var sessionId = await StartRecoverySession(email);

        // Cancel it from the authenticated (approved) device
        var cancelResponse = await authedClient.PostAsJsonAsync(
            $"/api/recovery/session/{sessionId}/cancel", new { });

        Assert.AreEqual(HttpStatusCode.OK, cancelResponse.StatusCode);

        // Verify session is cancelled
        var (scope, db) = GetDbContext();
        using (scope)
        {
            var session = await db.RecoverySessions.FirstAsync(s => s.Id == Guid.Parse(sessionId));
            Assert.AreEqual(RecoverySessionStatus.Cancelled, session.Status);
            Assert.IsNotNull(session.CancelledAt);
        }
    }

    [TestMethod]
    public async Task Cancelled_Session_Material_Returns_NotFound()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        var (_, authedClient) = await RegisterTestUserAsync(email);

        var sessionId = await StartRecoverySession(email);

        // Cancel
        var cancelResponse = await authedClient.PostAsJsonAsync(
            $"/api/recovery/session/{sessionId}/cancel", new { });
        Assert.AreEqual(HttpStatusCode.OK, cancelResponse.StatusCode);

        // Try to get material → should fail
        var materialResponse = await Client.PostAsJsonAsync($"/api/recovery/session/{sessionId}/material", new
        {
            replacementDevice = new { deviceName = "Recovery Device", platform = "test", clientType = "mobile", devicePublicKey = "" },
        });

        Assert.AreEqual(HttpStatusCode.NotFound, materialResponse.StatusCode);
    }

    [TestMethod]
    public async Task Cancel_Requires_Approved_Device()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        await RegisterTestUserAsync(email);
        var sessionId = await StartRecoverySession(email);

        var fakeClient = CreateAuthenticatedClient(Guid.NewGuid(), email, Guid.NewGuid());
        var response = await fakeClient.PostAsJsonAsync(
            $"/api/recovery/session/{sessionId}/cancel", new { });

        Assert.AreEqual(HttpStatusCode.Forbidden, response.StatusCode);
        fakeClient.Dispose();
    }

    // --- Active Session Limit ---

    [TestMethod]
    public async Task Cannot_Start_Second_Recovery_While_One_Is_Active()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        await RegisterTestUserAsync(email);

        // Start first recovery session
        await StartRecoverySession(email);

        // Try to start a second one
        var challengeResp = await Client.PostAsJsonAsync("/api/auth/login",
            TestDataHelper.CreateLoginRequest(email));
        var challenge = await challengeResp.Content.ReadFromJsonAsync<LoginChallengeResult>(JsonOptions);
        var nonce = Convert.FromBase64String(challenge!.Challenge.Nonce);
        var proof = TestDataHelper.ComputeClientProof(nonce, Guid.Parse(challenge.LoginSessionId));

        var redeemResponse = await Client.PostAsJsonAsync("/api/recovery/codes/redeem", new
        {
            email,
            recoveryCode = TestDataHelper.TestRecoveryCodes[1],
            verifierProof = new { loginSessionId = challenge.LoginSessionId, clientProof = proof },
        });

        Assert.AreEqual(HttpStatusCode.Conflict, redeemResponse.StatusCode);
    }

    [TestMethod]
    public async Task Can_Start_Recovery_After_Cancelling_Previous()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        var (_, authedClient) = await RegisterTestUserAsync(email);

        var sessionId = await StartRecoverySession(email);

        // Cancel first session
        var cancelResponse = await authedClient.PostAsJsonAsync(
            $"/api/recovery/session/{sessionId}/cancel", new { });
        Assert.AreEqual(HttpStatusCode.OK, cancelResponse.StatusCode);

        // Start a new recovery session — should succeed
        var newSessionId = await StartRecoverySession(email, 1);
        Assert.IsNotNull(newSessionId);
        Assert.AreNotEqual(sessionId, newSessionId);
    }

    // --- Helper ---

    private async Task<string> StartRecoverySession(string email, int codeIndex = 0)
    {
        var challengeResp = await Client.PostAsJsonAsync("/api/auth/login",
            TestDataHelper.CreateLoginRequest(email));
        var challenge = await challengeResp.Content.ReadFromJsonAsync<LoginChallengeResult>(JsonOptions);
        var nonce = Convert.FromBase64String(challenge!.Challenge.Nonce);
        var proof = TestDataHelper.ComputeClientProof(nonce, Guid.Parse(challenge.LoginSessionId));

        var redeemResponse = await Client.PostAsJsonAsync("/api/recovery/codes/redeem", new
        {
            email,
            recoveryCode = TestDataHelper.TestRecoveryCodes[codeIndex],
            verifierProof = new { loginSessionId = challenge.LoginSessionId, clientProof = proof },
        });

        Assert.AreEqual(HttpStatusCode.OK, redeemResponse.StatusCode,
            $"Recovery redeem failed with {redeemResponse.StatusCode}");
        var redeemResult = await redeemResponse.Content.ReadFromJsonAsync<JsonElement>();
        return redeemResult.GetProperty("recoverySessionId").GetString()!;
    }

    public TestContext TestContext { get; set; } = null!;
}
