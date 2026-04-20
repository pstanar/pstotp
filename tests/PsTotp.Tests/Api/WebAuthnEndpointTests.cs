using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using PsTotp.Server.Domain.Entities;
using PsTotp.Tests.Infrastructure;

namespace PsTotp.Tests.Api;

[TestClass]
public class WebAuthnEndpointTests : IntegrationTestBase
{
    // --- Registration ceremony ---

    [TestMethod]
    public async Task BeginRegistration_Returns_Ceremony_And_Options()
    {
        var (_, authedClient) = await RegisterTestUserAsync();

        var response = await authedClient.PostAsync("/api/webauthn/register/begin", null);
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);

        var json = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.IsTrue(json.TryGetProperty("ceremonyId", out _));
        Assert.IsTrue(json.TryGetProperty("publicKeyOptions", out var options));
        Assert.IsTrue(options.TryGetProperty("challenge", out _));
        Assert.IsTrue(options.TryGetProperty("rp", out _));
        Assert.IsTrue(options.TryGetProperty("user", out _));
    }

    [TestMethod]
    public async Task BeginRegistration_Requires_Approved_Device()
    {
        var fakeClient = CreateAuthenticatedClient(Guid.NewGuid(), "fake@example.com", Guid.NewGuid());

        var response = await fakeClient.PostAsync("/api/webauthn/register/begin", null);
        Assert.AreEqual(HttpStatusCode.Forbidden, response.StatusCode);
        fakeClient.Dispose();
    }

    [TestMethod]
    public async Task CompleteRegistration_Rejects_Invalid_Ceremony()
    {
        var (_, authedClient) = await RegisterTestUserAsync();

        var response = await authedClient.PostAsJsonAsync("/api/webauthn/register/complete", new
        {
            ceremonyId = Guid.NewGuid(),
            friendlyName = "Test Key",
            attestationResponse = new { },
        });
        Assert.AreEqual(HttpStatusCode.BadRequest, response.StatusCode);
    }

    // --- Assertion (login) ---

    [TestMethod]
    public async Task BeginAssertion_Returns_Generic_Error_For_Unknown_Email()
    {
        var response = await Client.PostAsJsonAsync("/api/webauthn/assert/begin", new
        {
            email = "nonexistent@example.com",
        });
        Assert.AreEqual(HttpStatusCode.BadRequest, response.StatusCode);

        var json = await response.Content.ReadFromJsonAsync<JsonElement>();
        var error = json.GetProperty("error").GetString();
        // Should NOT reveal whether the account exists
        Assert.AreEqual("Passkey authentication is not available", error);
    }

    [TestMethod]
    public async Task BeginAssertion_Returns_Generic_Error_When_No_Passkeys()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        await RegisterTestUserAsync(email);

        var response = await Client.PostAsJsonAsync("/api/webauthn/assert/begin", new
        {
            email,
        });
        Assert.AreEqual(HttpStatusCode.BadRequest, response.StatusCode);

        var json = await response.Content.ReadFromJsonAsync<JsonElement>();
        var error = json.GetProperty("error").GetString();
        // Same generic error as unknown email — no enumeration
        Assert.AreEqual("Passkey authentication is not available", error);
    }

    [TestMethod]
    public async Task BeginAssertion_Returns_Options_When_Credential_Exists()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        var (result, _) = await RegisterTestUserAsync(email);
        var userId = Guid.Parse(result.UserId);

        // Manually insert a WebAuthn credential
        await InsertTestCredential(userId, "Test Key");

        var response = await Client.PostAsJsonAsync("/api/webauthn/assert/begin", new
        {
            email,
        });
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);

        var json = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.IsTrue(json.TryGetProperty("ceremonyId", out _));
        Assert.IsTrue(json.TryGetProperty("publicKeyOptions", out var options));
        Assert.IsTrue(options.TryGetProperty("challenge", out _));
    }

    [TestMethod]
    public async Task BeginAssertion_Requires_Email_Or_RecoverySessionId()
    {
        var response = await Client.PostAsJsonAsync("/api/webauthn/assert/begin", new { });
        Assert.AreEqual(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [TestMethod]
    public async Task CompleteAssertion_Rejects_Invalid_Ceremony()
    {
        var response = await Client.PostAsJsonAsync("/api/webauthn/assert/complete", new
        {
            ceremonyId = Guid.NewGuid(),
            assertionResponse = new { },
        });
        Assert.AreEqual(HttpStatusCode.BadRequest, response.StatusCode);
    }

    // --- Credential management ---

    [TestMethod]
    public async Task ListCredentials_Returns_Empty_Initially()
    {
        var (_, authedClient) = await RegisterTestUserAsync();

        var response = await authedClient.GetAsync("/api/webauthn/credentials");
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);

        var json = await response.Content.ReadFromJsonAsync<JsonElement>();
        var credentials = json.GetProperty("credentials");
        Assert.AreEqual(0, credentials.GetArrayLength());
    }

    [TestMethod]
    public async Task ListCredentials_Returns_Inserted_Credential()
    {
        var (result, authedClient) = await RegisterTestUserAsync();
        var userId = Guid.Parse(result.UserId);
        await InsertTestCredential(userId, "My YubiKey");

        var response = await authedClient.GetAsync("/api/webauthn/credentials");
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);

        var json = await response.Content.ReadFromJsonAsync<JsonElement>();
        var credentials = json.GetProperty("credentials");
        Assert.AreEqual(1, credentials.GetArrayLength());
        Assert.AreEqual("My YubiKey", credentials[0].GetProperty("friendlyName").GetString());
    }

    [TestMethod]
    public async Task ListCredentials_Excludes_Revoked()
    {
        var (result, authedClient) = await RegisterTestUserAsync();
        var userId = Guid.Parse(result.UserId);
        await InsertTestCredential(userId, "Active Key");
        await InsertTestCredential(userId, "Revoked Key", revoked: true);

        var response = await authedClient.GetAsync("/api/webauthn/credentials");
        var json = await response.Content.ReadFromJsonAsync<JsonElement>();
        var credentials = json.GetProperty("credentials");
        Assert.AreEqual(1, credentials.GetArrayLength());
        Assert.AreEqual("Active Key", credentials[0].GetProperty("friendlyName").GetString());
    }

    [TestMethod]
    public async Task RenameCredential_Updates_Name()
    {
        var (result, authedClient) = await RegisterTestUserAsync();
        var userId = Guid.Parse(result.UserId);
        var credId = await InsertTestCredential(userId, "Old Name");

        var response = await authedClient.PutAsJsonAsync(
            $"/api/webauthn/credentials/{credId}/rename",
            new { friendlyName = "New Name" });
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);

        // Verify
        var listResp = await authedClient.GetAsync("/api/webauthn/credentials");
        var json = await listResp.Content.ReadFromJsonAsync<JsonElement>();
        Assert.AreEqual("New Name", json.GetProperty("credentials")[0].GetProperty("friendlyName").GetString());
    }

    [TestMethod]
    public async Task RenameCredential_Returns_NotFound_For_Unknown_Id()
    {
        var (_, authedClient) = await RegisterTestUserAsync();

        var response = await authedClient.PutAsJsonAsync(
            $"/api/webauthn/credentials/{Guid.NewGuid()}/rename",
            new { friendlyName = "Whatever" });
        Assert.AreEqual(HttpStatusCode.NotFound, response.StatusCode);
    }

    [TestMethod]
    public async Task RevokeCredential_Sets_RevokedAt()
    {
        var (result, authedClient) = await RegisterTestUserAsync();
        var userId = Guid.Parse(result.UserId);
        var credId = await InsertTestCredential(userId, "To Revoke");

        var response = await authedClient.PostAsync($"/api/webauthn/credentials/{credId}/revoke", null);
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);

        // Verify it's gone from the list
        var listResp = await authedClient.GetAsync("/api/webauthn/credentials");
        var json = await listResp.Content.ReadFromJsonAsync<JsonElement>();
        Assert.AreEqual(0, json.GetProperty("credentials").GetArrayLength());

        // Verify RevokedAt is set in DB
        var (scope, db) = GetDbContext();
        using (scope)
        {
            var cred = await db.WebAuthnCredentials.FirstAsync(c => c.Id == credId);
            Assert.IsNotNull(cred.RevokedAt);
        }
    }

    [TestMethod]
    public async Task RevokeCredential_Returns_NotFound_For_Unknown_Id()
    {
        var (_, authedClient) = await RegisterTestUserAsync();

        var response = await authedClient.PostAsync($"/api/webauthn/credentials/{Guid.NewGuid()}/revoke", null);
        Assert.AreEqual(HttpStatusCode.NotFound, response.StatusCode);
    }

    [TestMethod]
    public async Task Management_Endpoints_Require_Approved_Device()
    {
        var fakeClient = CreateAuthenticatedClient(Guid.NewGuid(), "fake@example.com", Guid.NewGuid());

        Assert.AreEqual(HttpStatusCode.Forbidden,
            (await fakeClient.GetAsync("/api/webauthn/credentials")).StatusCode);
        Assert.AreEqual(HttpStatusCode.Forbidden,
            (await fakeClient.PutAsJsonAsync($"/api/webauthn/credentials/{Guid.NewGuid()}/rename",
                new { friendlyName = "X" })).StatusCode);
        Assert.AreEqual(HttpStatusCode.Forbidden,
            (await fakeClient.PostAsync($"/api/webauthn/credentials/{Guid.NewGuid()}/revoke", null)).StatusCode);

        fakeClient.Dispose();
    }

    // --- Recovery step-up ---

    [TestMethod]
    public async Task Recovery_Requires_WebAuthn_When_Credential_Exists()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        var (result, _) = await RegisterTestUserAsync(email);
        var userId = Guid.Parse(result.UserId);
        await InsertTestCredential(userId, "Security Key");

        // Start recovery
        var challengeResp = await Client.PostAsJsonAsync("/api/auth/login",
            TestDataHelper.CreateLoginRequest(email));
        var challenge = await challengeResp.Content.ReadFromJsonAsync<LoginChallengeResult>(JsonOptions);
        var nonce = Convert.FromBase64String(challenge!.Challenge.Nonce);
        var proof = TestDataHelper.ComputeClientProof(nonce, Guid.Parse(challenge.LoginSessionId));

        var redeemResponse = await Client.PostAsJsonAsync("/api/recovery/codes/redeem", new
        {
            email,
            recoveryCode = TestDataHelper.TestRecoveryCodes[0],
            verifierProof = new { loginSessionId = challenge.LoginSessionId, clientProof = proof },
        });
        Assert.AreEqual(HttpStatusCode.OK, redeemResponse.StatusCode);

        var redeemResult = await redeemResponse.Content.ReadFromJsonAsync<JsonElement>();
        Assert.IsTrue(redeemResult.GetProperty("requiresWebAuthn").GetBoolean(),
            "Recovery should require WebAuthn when user has credentials");
    }

    // --- Helpers ---

    private async Task<Guid> InsertTestCredential(Guid userId, string name, bool revoked = false)
    {
        var id = Guid.NewGuid();
        var (scope, db) = GetDbContext();
        using (scope)
        {
            db.WebAuthnCredentials.Add(new WebAuthnCredential
            {
                Id = id,
                UserId = userId,
                CredentialId = Guid.NewGuid().ToByteArray(),
                PublicKey = new byte[32],
                SignCount = 0,
                FriendlyName = name,
                CreatedAt = DateTime.UtcNow,
                RevokedAt = revoked ? DateTime.UtcNow : null,
            });
            await db.SaveChangesAsync();
        }
        return id;
    }

    public TestContext TestContext { get; set; } = null!;
}
