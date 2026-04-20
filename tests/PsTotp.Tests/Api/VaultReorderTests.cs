using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using PsTotp.Tests.Infrastructure;

namespace PsTotp.Tests.Api;

[TestClass]
public class VaultReorderTests : IntegrationTestBase
{
    [TestMethod]
    public async Task Reorder_Updates_SortOrder()
    {
        var (_, authedClient) = await RegisterTestUserAsync();

        // Create 3 entries
        var ids = new List<string>();
        for (var i = 0; i < 3; i++)
        {
            var id = Guid.NewGuid().ToString();
            var payload = TestDataHelper.CreateVaultEntryPayload();
            var resp = await authedClient.PutAsJsonAsync($"/api/vault/{id}",
                new { entryPayload = payload, entryVersion = 0 });
            Assert.AreEqual(HttpStatusCode.OK, resp.StatusCode);
            ids.Add(id);
        }

        // Reverse the order
        var reversed = new List<string>(ids);
        reversed.Reverse();

        var reorderResp = await authedClient.PostAsJsonAsync("/api/vault/reorder",
            new { entryIds = reversed });
        Assert.AreEqual(HttpStatusCode.OK, reorderResp.StatusCode);

        // Fetch vault — entries should be in reversed order
        var vaultResp = await authedClient.GetAsync("/api/vault");
        var vault = await vaultResp.Content.ReadFromJsonAsync<JsonElement>();
        var entries = vault.GetProperty("entries");

        var returnedIds = new List<string>();
        for (var i = 0; i < entries.GetArrayLength(); i++)
        {
            var entry = entries[i];
            if (!entry.TryGetProperty("deletedAt", out var deletedAt) || deletedAt.ValueKind == JsonValueKind.Null)
                returnedIds.Add(entry.GetProperty("id").GetString()!);
        }

        Assert.AreEqual(reversed[0], returnedIds[0]);
        Assert.AreEqual(reversed[1], returnedIds[1]);
        Assert.AreEqual(reversed[2], returnedIds[2]);
    }

    [TestMethod]
    public async Task New_Entry_Placed_At_End()
    {
        var (_, authedClient) = await RegisterTestUserAsync();

        var id1 = Guid.NewGuid().ToString();
        var id2 = Guid.NewGuid().ToString();
        await authedClient.PutAsJsonAsync($"/api/vault/{id1}",
            new { entryPayload = TestDataHelper.CreateVaultEntryPayload(), entryVersion = 0 });
        await authedClient.PutAsJsonAsync($"/api/vault/{id2}",
            new { entryPayload = TestDataHelper.CreateVaultEntryPayload(), entryVersion = 0 });

        var vaultResp = await authedClient.GetAsync("/api/vault");
        var vault = await vaultResp.Content.ReadFromJsonAsync<JsonElement>();
        var entries = vault.GetProperty("entries");

        // Second entry should have higher sort order
        var sort0 = entries[0].GetProperty("sortOrder").GetInt32();
        var sort1 = entries[1].GetProperty("sortOrder").GetInt32();
        Assert.IsTrue(sort1 > sort0, $"Second entry sort {sort1} should be > first {sort0}");
    }

    [TestMethod]
    public async Task Reorder_Requires_Approved_Device()
    {
        var fakeClient = CreateAuthenticatedClient(Guid.NewGuid(), "fake@example.com", Guid.NewGuid());

        var response = await fakeClient.PostAsJsonAsync("/api/vault/reorder",
            new { entryIds = new[] { Guid.NewGuid().ToString() } });
        Assert.AreEqual(HttpStatusCode.Forbidden, response.StatusCode);
        fakeClient.Dispose();
    }

    public TestContext TestContext { get; set; } = null!;
}
