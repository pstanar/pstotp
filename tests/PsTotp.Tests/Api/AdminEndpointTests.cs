using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using PsTotp.Tests.Infrastructure;

namespace PsTotp.Tests.Api;

[TestClass]
public class AdminEndpointTests : IntegrationTestBase
{
    protected override Dictionary<string, string?> GetAdditionalConfig() => new()
    {
        ["Admins:0"] = "admin@example.com",
    };

    private async Task<(HttpClient adminClient, string adminUserId)> CreateAdminUserAsync()
    {
        var (result, client) = await RegisterTestUserAsync("admin@example.com");
        client.Dispose();
        var adminClient = CreateAuthenticatedClient(
            Guid.Parse(result.UserId), "admin@example.com", Guid.Parse(result.DeviceId), "Admin");
        return (adminClient, result.UserId);
    }

    [TestMethod]
    public async Task ListUsers_Returns_All_Users()
    {
        var (adminClient, _) = await CreateAdminUserAsync();
        await RegisterTestUserAsync("user1@example.com");
        await RegisterTestUserAsync("user2@example.com");

        var response = await adminClient.GetAsync("/api/admin/users");
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);

        var json = await response.Content.ReadFromJsonAsync<JsonElement>();
        var totalCount = json.GetProperty("totalCount").GetInt32();
        Assert.IsTrue(totalCount >= 3);
        adminClient.Dispose();
    }

    [TestMethod]
    public async Task ListUsers_Search_Filters_By_Email()
    {
        var (adminClient, _) = await CreateAdminUserAsync();
        await RegisterTestUserAsync("searchme@example.com");

        var response = await adminClient.GetAsync("/api/admin/users?search=searchme");
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);

        var json = await response.Content.ReadFromJsonAsync<JsonElement>();
        var users = json.GetProperty("users");
        Assert.AreEqual(1, users.GetArrayLength());
        adminClient.Dispose();
    }

    [TestMethod]
    public async Task DisableUser_Blocks_Login()
    {
        var (adminClient, _) = await CreateAdminUserAsync();
        var (targetResult, targetClient) = await RegisterTestUserAsync("target@example.com");
        targetClient.Dispose();

        var disableResp = await adminClient.PostAsync($"/api/admin/users/{targetResult.UserId}/disable", null);
        Assert.AreEqual(HttpStatusCode.OK, disableResp.StatusCode);

        // Verify user is disabled in DB
        var (scope, db) = GetDbContext();
        using (scope)
        {
            var user = await db.Users.FirstAsync(u => u.Id == Guid.Parse(targetResult.UserId));
            Assert.IsNotNull(user.DisabledAt);
        }
        adminClient.Dispose();
    }

    [TestMethod]
    public async Task EnableUser_After_Disable()
    {
        var (adminClient, _) = await CreateAdminUserAsync();
        var (targetResult, targetClient) = await RegisterTestUserAsync("enable-target@example.com");
        targetClient.Dispose();

        await adminClient.PostAsync($"/api/admin/users/{targetResult.UserId}/disable", null);
        var enableResp = await adminClient.PostAsync($"/api/admin/users/{targetResult.UserId}/enable", null);
        Assert.AreEqual(HttpStatusCode.OK, enableResp.StatusCode);

        var (scope, db) = GetDbContext();
        using (scope)
        {
            var user = await db.Users.FirstAsync(u => u.Id == Guid.Parse(targetResult.UserId));
            Assert.IsNull(user.DisabledAt);
        }
        adminClient.Dispose();
    }

    [TestMethod]
    public async Task Cannot_Disable_Self()
    {
        var (adminClient, adminUserId) = await CreateAdminUserAsync();

        var response = await adminClient.PostAsync($"/api/admin/users/{adminUserId}/disable", null);
        Assert.AreEqual(HttpStatusCode.BadRequest, response.StatusCode);
        adminClient.Dispose();
    }

    [TestMethod]
    public async Task Cannot_Delete_Self()
    {
        var (adminClient, adminUserId) = await CreateAdminUserAsync();

        var response = await adminClient.DeleteAsync($"/api/admin/users/{adminUserId}");
        Assert.AreEqual(HttpStatusCode.BadRequest, response.StatusCode);
        adminClient.Dispose();
    }

    [TestMethod]
    public async Task ForcePasswordReset_Sets_Flag()
    {
        var (adminClient, _) = await CreateAdminUserAsync();
        var (targetResult, targetClient) = await RegisterTestUserAsync("reset-target@example.com");
        targetClient.Dispose();

        var response = await adminClient.PostAsync($"/api/admin/users/{targetResult.UserId}/force-password-reset", null);
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);

        var (scope, db) = GetDbContext();
        using (scope)
        {
            var user = await db.Users.FirstAsync(u => u.Id == Guid.Parse(targetResult.UserId));
            Assert.IsTrue(user.ForcePasswordReset);
        }
        adminClient.Dispose();
    }

    [TestMethod]
    public async Task DeleteUser_Removes_All_Data()
    {
        var (adminClient, _) = await CreateAdminUserAsync();
        var (targetResult, targetClient) = await RegisterTestUserAsync("delete-target@example.com");
        targetClient.Dispose();
        var targetId = Guid.Parse(targetResult.UserId);

        var response = await adminClient.DeleteAsync($"/api/admin/users/{targetId}");
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);

        var (scope, db) = GetDbContext();
        using (scope)
        {
            Assert.IsFalse(await db.Users.AnyAsync(u => u.Id == targetId));
            Assert.IsFalse(await db.Devices.AnyAsync(d => d.UserId == targetId));
        }
        adminClient.Dispose();
    }

    [TestMethod]
    public async Task NonAdmin_Gets_Forbidden()
    {
        await RegisterTestUserAsync("admin@example.com");
        var (_, normalClient) = await RegisterTestUserAsync("normal@example.com");

        var response = await normalClient.GetAsync("/api/admin/users");
        Assert.AreEqual(HttpStatusCode.Forbidden, response.StatusCode);
        normalClient.Dispose();
    }

    [TestMethod]
    public async Task GetUserDetail_Returns_Devices()
    {
        var (adminClient, _) = await CreateAdminUserAsync();
        var (targetResult, targetClient) = await RegisterTestUserAsync("detail-target@example.com");
        targetClient.Dispose();

        var response = await adminClient.GetAsync($"/api/admin/users/{targetResult.UserId}");
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);

        var json = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.IsTrue(json.TryGetProperty("user", out _));
        Assert.IsTrue(json.TryGetProperty("devices", out var devices));
        Assert.IsTrue(devices.GetArrayLength() > 0);
        adminClient.Dispose();
    }

    public TestContext TestContext { get; set; } = null!;
}
