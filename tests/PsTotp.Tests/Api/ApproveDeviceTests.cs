using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using Microsoft.EntityFrameworkCore;
using PsTotp.Server.Domain.Entities;
using PsTotp.Tests.Infrastructure;

namespace PsTotp.Tests.Api;

[TestClass]
public class ApproveDeviceTests : IntegrationTestBase
{
    [TestMethod]
    public async Task Approve_Changes_Device_Status_To_Approved()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        var (_, approverClient) = await RegisterTestUserAsync(email);

        // Login from new device → pending
        var loginResult = await LoginTestUserAsync(email, "New Device");
        Assert.AreEqual("pending", loginResult.Device.Status);

        var pendingDeviceId = loginResult.Device.DeviceId;

        // Approve from the original (approved) device
        var dummyNonce = Convert.ToBase64String(RandomNumberGenerator.GetBytes(12));
        var dummyCiphertext = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48));

        var response = await approverClient.PostAsJsonAsync($"/api/devices/{pendingDeviceId}/approve", new
        {
            approvalRequestId = pendingDeviceId,
            approvalAuth = new { type = "device" },
            deviceEnvelope = new { ciphertext = dummyCiphertext, nonce = dummyNonce, version = 1 },
        }, cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);

        var (scope, db) = GetDbContext();
        using (scope)
        {
            var device = await db.Devices.FirstAsync(d => d.Id == Guid.Parse(pendingDeviceId), TestContext.CancellationToken);
            Assert.AreEqual(DeviceStatus.Approved, device.Status);
            Assert.IsNotNull(device.ApprovedAt);

            // Device envelope should be stored
            var envelope = await db.VaultKeyEnvelopes.FirstOrDefaultAsync(e =>
                e.DeviceId == Guid.Parse(pendingDeviceId) && e.EnvelopeType == EnvelopeType.Device, TestContext.CancellationToken);
            Assert.IsNotNull(envelope);
        }
    }

    [TestMethod]
    public async Task Approve_From_Pending_Device_Is_Forbidden()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        await RegisterTestUserAsync(email);

        // Login from two new devices → both pending
        var login1 = await LoginTestUserAsync(email, "Device A");
        var login2 = await LoginTestUserAsync(email, "Device B");

        Assert.AreEqual("pending", login1.Device.Status);
        Assert.AreEqual("pending", login2.Device.Status);

        // Try to approve Device B from Device A (pending) — should be forbidden
        // Need the actual userId from DB
        Guid userId;
        {
            var (scope, db) = GetDbContext();
            using (scope)
            {
                var user = await db.Users.FirstAsync(u => u.Email == email, TestContext.CancellationToken);
                userId = user.Id;
            }
        }
        var pendingClient = CreateAuthenticatedClient(
            userId, email, Guid.Parse(login1.Device.DeviceId));

        var dummyNonce = Convert.ToBase64String(RandomNumberGenerator.GetBytes(12));
        var dummyCiphertext = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48));

        var response = await pendingClient.PostAsJsonAsync($"/api/devices/{login2.Device.DeviceId}/approve", new
        {
            approvalRequestId = login2.Device.DeviceId,
            approvalAuth = new { type = "device" },
            deviceEnvelope = new { ciphertext = dummyCiphertext, nonce = dummyNonce, version = 1 },
        }, cancellationToken: TestContext.CancellationToken);

        // Should be 403 Forbidden (caller device is not approved)
        Assert.AreEqual(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [TestMethod]
    public async Task Reject_Removes_Pending_Device()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        var (_, approverClient) = await RegisterTestUserAsync(email);

        var loginResult = await LoginTestUserAsync(email, "New Device");
        var pendingDeviceId = loginResult.Device.DeviceId;

        var response = await approverClient.PostAsync($"/api/devices/{pendingDeviceId}/reject", null, TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);

        var (scope, db) = GetDbContext();
        using (scope)
        {
            var device = await db.Devices.FirstAsync(d => d.Id == Guid.Parse(pendingDeviceId), TestContext.CancellationToken);
            Assert.AreEqual(DeviceStatus.Revoked, device.Status);
            Assert.IsNotNull(device.RevokedAt);
        }
    }

    public TestContext TestContext { get; set; } = null!;
}
