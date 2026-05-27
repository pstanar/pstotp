using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;

using PsTotp.Tests.Infrastructure;

namespace PsTotp.Tests.Api;

[TestClass]
public class AdminSettingsTests : IntegrationTestBase
{
    protected override Dictionary<string, string?> GetAdditionalConfig() => new()
    {
        ["Admins:0"] = "admin@example.com",
    };

    private async Task<HttpClient> CreateAdminClientAsync()
    {
        var (result, client) = await RegisterTestUserAsync("admin@example.com");
        client.Dispose();
        return CreateAuthenticatedClient(
            Guid.Parse(result.UserId),
            "admin@example.com",
            Guid.Parse(result.DeviceId),
            "Admin");
    }

    [TestMethod]
    public async Task Settings_Default_Is_Registration_Enabled()
    {
        var adminClient = await CreateAdminClientAsync();
        var response = await adminClient.GetAsync("/api/admin/settings");
        response.EnsureSuccessStatusCode();
        var json = await response.Content.ReadFromJsonAsync<JsonElement>(JsonOptions);
        Assert.IsTrue(json.GetProperty("registrationEnabled").GetBoolean());
    }

    [TestMethod]
    public async Task Disabling_Registration_Returns_403_From_Register_Begin()
    {
        var adminClient = await CreateAdminClientAsync();

        var disable = await adminClient.PutAsJsonAsync(
            "/api/admin/settings/registration", new { enabled = false });
        disable.EnsureSuccessStatusCode();

        var attempt = await Client.PostAsJsonAsync(
            "/api/auth/register/begin",
            new { email = $"after-disable-{Guid.NewGuid():N}@example.com" });
        Assert.AreEqual(HttpStatusCode.Forbidden, attempt.StatusCode);
    }

    [TestMethod]
    public async Task Re_Enabling_Registration_Restores_Begin_Success()
    {
        var adminClient = await CreateAdminClientAsync();

        await adminClient.PutAsJsonAsync(
            "/api/admin/settings/registration", new { enabled = false });
        await adminClient.PutAsJsonAsync(
            "/api/admin/settings/registration", new { enabled = true });

        var attempt = await Client.PostAsJsonAsync(
            "/api/auth/register/begin",
            new { email = $"after-reenable-{Guid.NewGuid():N}@example.com" });
        Assert.AreNotEqual(HttpStatusCode.Forbidden, attempt.StatusCode);
    }

    [TestMethod]
    public async Task Toggle_Writes_Audit_Event()
    {
        var adminClient = await CreateAdminClientAsync();

        await adminClient.PutAsJsonAsync(
            "/api/admin/settings/registration", new { enabled = false });

        var (scope, db) = GetDbContext();
        using (scope)
        {
            var hasAudit = await db.AuditEvents.AnyAsync(e =>
                e.EventType == "registration_enabled_changed");
            Assert.IsTrue(hasAudit, "toggle should write an audit event");
        }
    }
}
