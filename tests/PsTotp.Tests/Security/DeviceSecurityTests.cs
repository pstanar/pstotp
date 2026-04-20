using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using Microsoft.EntityFrameworkCore;
using PsTotp.Server.Domain.Entities;
using PsTotp.Tests.Infrastructure;

namespace PsTotp.Tests.Security;

[TestClass]
public class DeviceSecurityTests : IntegrationTestBase
{
    [TestMethod]
    public async Task Revoked_Device_Cannot_Refresh()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        var (_, approverClient) = await RegisterTestUserAsync(email);

        // Login from new device with a known public key → pending
        var newDeviceKey = Convert.ToBase64String(RandomNumberGenerator.GetBytes(65));
        var loginResult = await LoginTestUserAsync(email, "New Device", newDeviceKey);
        var pendingDeviceId = loginResult.Device.DeviceId;

        // Approve the new device
        var dummyNonce = Convert.ToBase64String(RandomNumberGenerator.GetBytes(12));
        var dummyCiphertext = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48));
        await approverClient.PostAsJsonAsync($"/api/devices/{pendingDeviceId}/approve", new
        {
            approvalRequestId = pendingDeviceId,
            approvalAuth = new { type = "device" },
            deviceEnvelope = new { ciphertext = dummyCiphertext, nonce = dummyNonce, version = 1 },
        });

        // Login again with the same public key → should match approved device
        var login2 = await LoginTestUserAsync(email, "New Device", newDeviceKey);
        Assert.AreEqual("approved", login2.Device.Status);
        Assert.IsNotNull(login2.RefreshToken);

        // Revoke the device from the approver
        await approverClient.PostAsync($"/api/devices/{pendingDeviceId}/revoke", null);

        // Revoked device's refresh token should now fail
        var refreshResponse = await Client.PostAsJsonAsync("/api/auth/refresh", new
        {
            refreshToken = login2.RefreshToken,
        });
        Assert.AreEqual(HttpStatusCode.Unauthorized, refreshResponse.StatusCode);
    }

    [TestMethod]
    public async Task Device_Matched_By_PublicKey_Not_Name()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";

        // Register with a specific public key
        var registerRequest = TestDataHelper.CreateRegisterRequest(email);
        await Client.PostAsJsonAsync("/api/auth/register", registerRequest);

        // Login with same device name but different public key → should create NEW pending device
        var differentKey = Convert.ToBase64String(RandomNumberGenerator.GetBytes(65));
        var loginResponse = await Client.PostAsJsonAsync("/api/auth/login", new
        {
            email,
            device = new
            {
                deviceName = "Test Device", // Same name as registration
                platform = "test",
                clientType = "mobile",
                devicePublicKey = differentKey, // Different key
            },
        });
        loginResponse.EnsureSuccessStatusCode();

        var challenge = await loginResponse.Content.ReadFromJsonAsync<LoginChallengeResult>(JsonOptions);
        var nonce = Convert.FromBase64String(challenge!.Challenge.Nonce);
        var proof = TestDataHelper.ComputeClientProof(nonce, Guid.Parse(challenge.LoginSessionId));

        var completeResponse = await Client.PostAsJsonAsync("/api/auth/login/complete", new
        {
            loginSessionId = challenge.LoginSessionId,
            clientProof = proof,
        });
        completeResponse.EnsureSuccessStatusCode();

        var result = await completeResponse.Content.ReadFromJsonAsync<LoginResult>(JsonOptions);

        // Should be PENDING because the public key doesn't match the approved device
        Assert.AreEqual("pending", result!.Device.Status);

        // Verify DB has 2 devices
        var (scope, db) = GetDbContext();
        using (scope)
        {
            var user = await db.Users.FirstAsync(u => u.Email == email);
            var devices = await db.Devices.Where(d => d.UserId == user.Id).ToListAsync();
            Assert.HasCount(2, devices);
            Assert.IsTrue(devices.Any(d => d.Status == DeviceStatus.Approved));
            Assert.IsTrue(devices.Any(d => d.Status == DeviceStatus.Pending && d.DevicePublicKey == differentKey));
        }
    }

    [TestMethod]
    public async Task Revoke_Device_Requires_Approved_Caller()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        var (reg, _) = await RegisterTestUserAsync(email);

        // Login from new device → pending
        var loginResult = await LoginTestUserAsync(email, "New Device");

        // Get userId
        Guid userId;
        {
            var (scope, db) = GetDbContext();
            using (scope)
            {
                var user = await db.Users.FirstAsync(u => u.Email == email);
                userId = user.Id;
            }
        }

        // Try to revoke the original device from the pending device → should be forbidden
        var pendingClient = CreateAuthenticatedClient(
            userId, email, Guid.Parse(loginResult.Device.DeviceId));

        var response = await pendingClient.PostAsync($"/api/devices/{reg.DeviceId}/revoke", null);
        Assert.AreEqual(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [TestMethod]
    public async Task Password_Change_Requires_Approved_Device()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        await RegisterTestUserAsync(email);

        // Login from new device → pending
        var loginResult = await LoginTestUserAsync(email, "New Device");

        // Get userId
        Guid userId;
        {
            var (scope, db) = GetDbContext();
            using (scope)
            {
                var user = await db.Users.FirstAsync(u => u.Email == email);
                userId = user.Id;
            }
        }

        // Authenticate as pending device
        var pendingClient = CreateAuthenticatedClient(
            userId, email, Guid.Parse(loginResult.Device.DeviceId));

        // Try to change password from pending device
        var dummyNonce = Convert.ToBase64String(RandomNumberGenerator.GetBytes(12));
        var dummyCiphertext = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48));

        var response = await pendingClient.PostAsJsonAsync("/api/account/password/change", new
        {
            currentProof = new { loginSessionId = Guid.NewGuid().ToString(), clientProof = Convert.ToBase64String(new byte[32]) },
            newVerifier = new
            {
                verifier = TestDataHelper.NewTestVerifierBase64,
                kdf = new { algorithm = "argon2id", memoryMb = 64, iterations = 3, parallelism = 4, salt = TestDataHelper.TestSaltBase64 },
            },
            newPasswordEnvelope = new { ciphertext = dummyCiphertext, nonce = dummyNonce, version = 1 },
        });

        Assert.AreEqual(HttpStatusCode.Forbidden, response.StatusCode);
    }

    public TestContext TestContext { get; set; } = null!;
}
