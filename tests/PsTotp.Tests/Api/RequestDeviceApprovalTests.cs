using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using PsTotp.Tests.Infrastructure;

namespace PsTotp.Tests.Api;

[TestClass]
public class RequestDeviceApprovalTests : IntegrationTestBase
{
    [TestMethod]
    public async Task Pending_Device_Cannot_Access_Vault()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        await RegisterTestUserAsync(email);

        // Login from new device → pending
        var loginResult = await LoginTestUserAsync(email, "New Device");
        Assert.AreEqual("pending", loginResult.Device.Status);

        // Get actual userId
        Guid userId;
        {
            var (scope, db) = GetDbContext();
            using (scope)
            {
                var user = await db.Users.FirstAsync(u => u.Email == email, TestContext.CancellationToken);
                userId = user.Id;
            }
        }

        // Authenticate as the pending device
        var pendingClient = CreateAuthenticatedClient(
            userId, email, Guid.Parse(loginResult.Device.DeviceId));

        var response = await pendingClient.GetAsync("/api/vault", TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [TestMethod]
    public async Task Pending_Device_Appears_In_Device_List()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        var (_, approverClient) = await RegisterTestUserAsync(email);

        // Login from new device → pending
        await LoginTestUserAsync(email, "New Device");

        // Get device list from approved device
        var response = await approverClient.GetFromJsonAsync<JsonElement>("/api/devices", TestContext.CancellationToken);
        var devices = response.GetProperty("devices");

        Assert.AreEqual(2, devices.GetArrayLength());

        var pendingDevice = devices.EnumerateArray()
            .FirstOrDefault(d => d.GetProperty("status").GetString() == "pending");

        Assert.AreNotEqual(JsonValueKind.Undefined, pendingDevice.ValueKind);
        Assert.AreEqual("New Device", pendingDevice.GetProperty("deviceName").GetString());
        Assert.IsFalse(string.IsNullOrEmpty(
            pendingDevice.GetProperty("approvalRequestId").GetString()));
    }

    public TestContext TestContext { get; set; } = null!;
}
