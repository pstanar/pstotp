using System.Net;
using System.Net.Http.Json;
using Microsoft.EntityFrameworkCore;
using PsTotp.Server.Domain.Entities;
using PsTotp.Tests.Infrastructure;

namespace PsTotp.Tests.Api;

[TestClass]
public class RegisterUserTests : IntegrationTestBase
{
    [TestMethod]
    public async Task Register_Creates_User_With_Approved_Device()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        var request = TestDataHelper.CreateRegisterRequest(email);

        var response = await Client.PostAsJsonAsync("/api/auth/register", request, cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);

        var result = await response.Content.ReadFromJsonAsync<RegisterResult>(JsonOptions, TestContext.CancellationToken);
        Assert.IsNotNull(result);
        Assert.IsFalse(string.IsNullOrEmpty(result.UserId));
        Assert.IsFalse(string.IsNullOrEmpty(result.DeviceId));

        var (scope, db) = GetDbContext();
        using (scope)
        {
            var user = await db.Users.FirstOrDefaultAsync(u => u.Email == email, TestContext.CancellationToken);
            Assert.IsNotNull(user);

            var device = await db.Devices.FirstOrDefaultAsync(d => d.UserId == user.Id, TestContext.CancellationToken);
            Assert.IsNotNull(device);
            Assert.AreEqual(DeviceStatus.Approved, device.Status);

            var envelopes = await db.VaultKeyEnvelopes.Where(e => e.UserId == user.Id).ToListAsync(TestContext.CancellationToken);
            Assert.HasCount(3, envelopes);
        }
    }

    [TestMethod]
    public async Task Register_Rejects_Duplicate_Email()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";

        var response1 = await Client.PostAsJsonAsync("/api/auth/register",
            TestDataHelper.CreateRegisterRequest(email), cancellationToken: TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.OK, response1.StatusCode);

        var response2 = await Client.PostAsJsonAsync("/api/auth/register",
            TestDataHelper.CreateRegisterRequest(email), cancellationToken: TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.Conflict, response2.StatusCode);
    }

    [TestMethod]
    public async Task Register_Stores_Recovery_Code_Hashes()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";

        var response = await Client.PostAsJsonAsync("/api/auth/register",
            TestDataHelper.CreateRegisterRequest(email), cancellationToken: TestContext.CancellationToken);
        response.EnsureSuccessStatusCode();

        var (scope, db) = GetDbContext();
        using (scope)
        {
            var user = await db.Users.FirstOrDefaultAsync(u => u.Email == email, TestContext.CancellationToken);
            Assert.IsNotNull(user);

            var codes = await db.RecoveryCodes.Where(c => c.UserId == user.Id).ToListAsync(TestContext.CancellationToken);
            Assert.HasCount(8, codes);
            for (var i = 0; i < 8; i++)
                Assert.IsTrue(codes.Any(c => c.CodeSlot == i));
        }
    }

    public TestContext TestContext { get; set; } = null!;
}
