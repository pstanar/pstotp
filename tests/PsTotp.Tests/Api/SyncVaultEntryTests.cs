using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using PsTotp.Tests.Infrastructure;

namespace PsTotp.Tests.Api;

[TestClass]
public class SyncVaultEntryTests : IntegrationTestBase
{
    [TestMethod]
    public async Task Put_Creates_New_Entry()
    {
        var (_, client) = await RegisterTestUserAsync();
        var entryId = Guid.NewGuid();

        var response = await client.PutAsJsonAsync($"/api/vault/{entryId}", new
        {
            entryPayload = TestDataHelper.CreateVaultEntryPayload(),
            entryVersion = 0,
        }, cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);
        var result = await response.Content.ReadFromJsonAsync<JsonElement>(TestContext.CancellationToken);
        Assert.AreEqual(1, result.GetProperty("entryVersion").GetInt32());
    }

    [TestMethod]
    public async Task Put_Updates_Existing_Entry_With_Correct_Version()
    {
        var (_, client) = await RegisterTestUserAsync();
        var entryId = Guid.NewGuid();

        // Create v1
        await client.PutAsJsonAsync($"/api/vault/{entryId}", new
        {
            entryPayload = TestDataHelper.CreateVaultEntryPayload(),
            entryVersion = 0,
        }, cancellationToken: TestContext.CancellationToken);

        // Update with v1 → should become v2
        var response = await client.PutAsJsonAsync($"/api/vault/{entryId}", new
        {
            entryPayload = TestDataHelper.CreateVaultEntryPayload(),
            entryVersion = 1,
        }, cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);
        var result = await response.Content.ReadFromJsonAsync<JsonElement>(TestContext.CancellationToken);
        Assert.AreEqual(2, result.GetProperty("entryVersion").GetInt32());
    }

    [TestMethod]
    public async Task Put_Rejects_Stale_Version()
    {
        var (_, client) = await RegisterTestUserAsync();
        var entryId = Guid.NewGuid();

        // Create v1
        await client.PutAsJsonAsync($"/api/vault/{entryId}", new
        {
            entryPayload = TestDataHelper.CreateVaultEntryPayload(),
            entryVersion = 0,
        }, cancellationToken: TestContext.CancellationToken);

        // Update v1 → v2
        await client.PutAsJsonAsync($"/api/vault/{entryId}", new
        {
            entryPayload = TestDataHelper.CreateVaultEntryPayload(),
            entryVersion = 1,
        }, cancellationToken: TestContext.CancellationToken);

        // Try update with stale v1
        var response = await client.PutAsJsonAsync($"/api/vault/{entryId}", new
        {
            entryPayload = TestDataHelper.CreateVaultEntryPayload(),
            entryVersion = 1,
        }, cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.Conflict, response.StatusCode);
    }

    [TestMethod]
    public async Task Delete_Soft_Deletes_Entry()
    {
        var (_, authClient) = await RegisterTestUserAsync();
        var entryId = Guid.NewGuid();

        // Create entry
        await authClient.PutAsJsonAsync($"/api/vault/{entryId}", new
        {
            entryPayload = TestDataHelper.CreateVaultEntryPayload(),
            entryVersion = 0,
        }, cancellationToken: TestContext.CancellationToken);

        // Delete
        var deleteResponse = await authClient.DeleteAsync($"/api/vault/{entryId}", TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.OK, deleteResponse.StatusCode);

        // Verify still in vault but with deletedAt
        var getResponse = await authClient.GetFromJsonAsync<JsonElement>("/api/vault", TestContext.CancellationToken);
        var entries = getResponse.GetProperty("entries");
        Assert.AreEqual(1, entries.GetArrayLength());
        Assert.IsFalse(string.IsNullOrEmpty(
            entries[0].GetProperty("deletedAt").GetString()));
    }

    public TestContext TestContext { get; set; } = null!;
}
