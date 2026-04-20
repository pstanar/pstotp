using System.Net.Http.Json;
using Microsoft.EntityFrameworkCore;
using PsTotp.Server.Domain.Entities;
using PsTotp.Tests.Infrastructure;

namespace PsTotp.Tests.Api;

[TestClass]
public class RegisterDeviceTests : IntegrationTestBase
{
    [TestMethod]
    public async Task Login_From_New_Device_Creates_Pending_Device()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        await Client.PostAsJsonAsync("/api/auth/register", TestDataHelper.CreateRegisterRequest(email), cancellationToken: TestContext.CancellationToken);

        // Login from a different device name
        var loginResult = await LoginTestUserAsync(email, "New Device");

        Assert.AreEqual("pending", loginResult.Device.Status);

        var (scope, db) = GetDbContext();
        using (scope)
        {
            var devices = await db.Devices.Where(d => d.DeviceName == "New Device").ToListAsync(TestContext.CancellationToken);
            Assert.HasCount(1, devices);
            Assert.AreEqual(DeviceStatus.Pending, devices[0].Status);
        }
    }

    [TestMethod]
    public async Task Login_From_Existing_Approved_Device_Reuses_Device()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        await Client.PostAsJsonAsync("/api/auth/register", TestDataHelper.CreateRegisterRequest(email), cancellationToken: TestContext.CancellationToken);

        // Login from same device name as registration ("Test Device")
        var loginResult = await LoginTestUserAsync(email, "Test Device");

        Assert.AreEqual("approved", loginResult.Device.Status);

        var (scope, db) = GetDbContext();
        using (scope)
        {
            var user = await db.Users.FirstAsync(u => u.Email == email, TestContext.CancellationToken);
            var devices = await db.Devices.Where(d => d.UserId == user.Id).ToListAsync(TestContext.CancellationToken);
            // Should be only 1 device, not 2
            Assert.HasCount(1, devices);
        }
    }

    public TestContext TestContext { get; set; } = null!;
}
