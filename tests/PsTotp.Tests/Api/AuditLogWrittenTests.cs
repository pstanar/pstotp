using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using PsTotp.Tests.Infrastructure;

namespace PsTotp.Tests.Api;

[TestClass]
public class AuditLogWrittenTests : IntegrationTestBase
{
    [TestMethod]
    public async Task Registration_Creates_Audit_Event()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        await Client.PostAsJsonAsync("/api/auth/register", TestDataHelper.CreateRegisterRequest(email), cancellationToken: TestContext.CancellationToken);

        var (scope, db) = GetDbContext();
        using (scope)
        {
            var user = await db.Users.FirstAsync(u => u.Email == email, TestContext.CancellationToken);
            var evt = await db.AuditEvents.FirstOrDefaultAsync(e =>
                e.UserId == user.Id && e.EventType == "account_created", TestContext.CancellationToken);
            Assert.IsNotNull(evt);
        }
    }

    [TestMethod]
    public async Task Login_Creates_Audit_Event()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        await Client.PostAsJsonAsync("/api/auth/register", TestDataHelper.CreateRegisterRequest(email), cancellationToken: TestContext.CancellationToken);
        await LoginTestUserAsync(email);

        var (scope, db) = GetDbContext();
        using (scope)
        {
            var user = await db.Users.FirstAsync(u => u.Email == email, TestContext.CancellationToken);
            var evt = await db.AuditEvents.FirstOrDefaultAsync(e =>
                e.UserId == user.Id && e.EventType == "login_success", TestContext.CancellationToken);
            Assert.IsNotNull(evt);
        }
    }

    [TestMethod]
    public async Task Failed_Login_Creates_Audit_Event()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        await Client.PostAsJsonAsync("/api/auth/register", TestDataHelper.CreateRegisterRequest(email), cancellationToken: TestContext.CancellationToken);

        // Start login challenge
        var challengeResponse = await Client.PostAsJsonAsync("/api/auth/login",
            TestDataHelper.CreateLoginRequest(email), cancellationToken: TestContext.CancellationToken);
        var challenge = await challengeResponse.Content.ReadFromJsonAsync<LoginChallengeResult>(JsonOptions, TestContext.CancellationToken);

        // Submit wrong proof
        var wrongProof = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32));
        var completeResponse = await Client.PostAsJsonAsync("/api/auth/login/complete", new
        {
            loginSessionId = challenge!.LoginSessionId,
            clientProof = wrongProof,
        }, cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.Unauthorized, completeResponse.StatusCode);

        var (scope, db) = GetDbContext();
        using (scope)
        {
            var user = await db.Users.FirstAsync(u => u.Email == email, TestContext.CancellationToken);
            var evt = await db.AuditEvents.FirstOrDefaultAsync(e =>
                e.UserId == user.Id && e.EventType == "login_failed", TestContext.CancellationToken);
            Assert.IsNotNull(evt);
        }
    }

    [TestMethod]
    public async Task Device_Approval_Creates_Audit_Event()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        var (_, approverClient) = await RegisterTestUserAsync(email);

        var loginResult = await LoginTestUserAsync(email, "New Device");
        var pendingDeviceId = loginResult.Device.DeviceId;

        var dummyNonce = Convert.ToBase64String(RandomNumberGenerator.GetBytes(12));
        var dummyCiphertext = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48));

        await approverClient.PostAsJsonAsync($"/api/devices/{pendingDeviceId}/approve", new
        {
            approvalRequestId = pendingDeviceId,
            approvalAuth = new { type = "device" },
            deviceEnvelope = new { ciphertext = dummyCiphertext, nonce = dummyNonce, version = 1 },
        }, cancellationToken: TestContext.CancellationToken);

        var (scope, db) = GetDbContext();
        using (scope)
        {
            var evt = await db.AuditEvents.FirstOrDefaultAsync(e =>
                e.DeviceId == Guid.Parse(pendingDeviceId) && e.EventType == "device_approved", TestContext.CancellationToken);
            Assert.IsNotNull(evt);
            Assert.IsNotNull(evt.EventData); // Should contain ApprovedBy
        }
    }

    [TestMethod]
    public async Task Device_Revocation_Creates_Audit_Event()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        var (_, approverClient) = await RegisterTestUserAsync(email);

        // Create and approve a second device
        var loginResult = await LoginTestUserAsync(email, "New Device");
        var pendingDeviceId = loginResult.Device.DeviceId;

        var dummyNonce = Convert.ToBase64String(RandomNumberGenerator.GetBytes(12));
        var dummyCiphertext = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48));

        await approverClient.PostAsJsonAsync($"/api/devices/{pendingDeviceId}/approve", new
        {
            approvalRequestId = pendingDeviceId,
            approvalAuth = new { type = "device" },
            deviceEnvelope = new { ciphertext = dummyCiphertext, nonce = dummyNonce, version = 1 },
        }, cancellationToken: TestContext.CancellationToken);

        // Revoke the second device
        await approverClient.PostAsync($"/api/devices/{pendingDeviceId}/revoke", null, TestContext.CancellationToken);

        var (scope, db) = GetDbContext();
        using (scope)
        {
            var evt = await db.AuditEvents.FirstOrDefaultAsync(e =>
                e.DeviceId == Guid.Parse(pendingDeviceId) && e.EventType == "device_revoked", TestContext.CancellationToken);
            Assert.IsNotNull(evt);
        }
    }

    [TestMethod]
    public async Task Audit_Events_Endpoint_Returns_User_Events()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        var (_, authClient) = await RegisterTestUserAsync(email);

        // Login to generate another audit event
        await LoginTestUserAsync(email);

        var response = await authClient.GetFromJsonAsync<JsonElement>("/api/security/audit-events", TestContext.CancellationToken);
        var events = response.GetProperty("events");

        Assert.IsGreaterThanOrEqualTo(2, events.GetArrayLength()); // at least account_created + login_success
    }

    public TestContext TestContext { get; set; } = null!;
}
