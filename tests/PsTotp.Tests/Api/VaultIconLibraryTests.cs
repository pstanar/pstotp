using System.Net;
using System.Net.Http.Json;
using PsTotp.Server.Application.DTOs;
using PsTotp.Tests.Infrastructure;

namespace PsTotp.Tests.Api;

[TestClass]
public class VaultIconLibraryTests : IntegrationTestBase
{
    [TestMethod]
    public async Task Get_Returns_Empty_Payload_When_Library_Does_Not_Exist()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        var (_, client) = await RegisterTestUserAsync(email);

        var response = await client.GetAsync("/api/vault/icon-library", TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);
        var payload = await response.Content.ReadFromJsonAsync<IconLibraryResponse>(JsonOptions, TestContext.CancellationToken);
        Assert.IsNotNull(payload);
        Assert.AreEqual(string.Empty, payload.EncryptedPayload);
        Assert.AreEqual(0, payload.Version);
        Assert.IsNull(payload.UpdatedAt);
    }

    [TestMethod]
    public async Task Put_Creates_Library_On_First_Write()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        var (_, client) = await RegisterTestUserAsync(email);

        var blob = Convert.ToBase64String([1, 2, 3, 4, 5]);
        var response = await client.PutAsJsonAsync("/api/vault/icon-library",
            new IconLibraryUpdateRequest(blob, 0), cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);
        var payload = await response.Content.ReadFromJsonAsync<IconLibraryUpdateResponse>(JsonOptions, TestContext.CancellationToken);
        Assert.IsNotNull(payload);
        Assert.AreEqual(1, payload.Version);

        var get = await client.GetAsync("/api/vault/icon-library", TestContext.CancellationToken);
        var got = await get.Content.ReadFromJsonAsync<IconLibraryResponse>(JsonOptions, TestContext.CancellationToken);
        Assert.IsNotNull(got);
        Assert.AreEqual(blob, got.EncryptedPayload);
        Assert.AreEqual(1, got.Version);
    }

    [TestMethod]
    public async Task Put_Rejects_Empty_Payload()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        var (_, client) = await RegisterTestUserAsync(email);

        var response = await client.PutAsJsonAsync("/api/vault/icon-library",
            new IconLibraryUpdateRequest(string.Empty, 0), cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [TestMethod]
    public async Task Put_Rejects_NonBase64_Payload()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        var (_, client) = await RegisterTestUserAsync(email);

        var response = await client.PutAsJsonAsync("/api/vault/icon-library",
            new IconLibraryUpdateRequest("not base64!!!", 0), cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [TestMethod]
    public async Task Put_First_Write_With_Nonzero_Version_Is_Rejected()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        var (_, client) = await RegisterTestUserAsync(email);

        var blob = Convert.ToBase64String([1, 2, 3]);
        var response = await client.PutAsJsonAsync("/api/vault/icon-library",
            new IconLibraryUpdateRequest(blob, 1), cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.Conflict, response.StatusCode);
    }

    [TestMethod]
    public async Task Put_Increments_Version_On_Each_Write()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        var (_, client) = await RegisterTestUserAsync(email);

        var blobA = Convert.ToBase64String([1, 2, 3]);
        var blobB = Convert.ToBase64String([4, 5, 6, 7]);

        var r1 = await client.PutAsJsonAsync("/api/vault/icon-library",
            new IconLibraryUpdateRequest(blobA, 0), cancellationToken: TestContext.CancellationToken);
        var v1 = (await r1.Content.ReadFromJsonAsync<IconLibraryUpdateResponse>(JsonOptions, TestContext.CancellationToken))!.Version;

        var r2 = await client.PutAsJsonAsync("/api/vault/icon-library",
            new IconLibraryUpdateRequest(blobB, v1), cancellationToken: TestContext.CancellationToken);
        var v2 = (await r2.Content.ReadFromJsonAsync<IconLibraryUpdateResponse>(JsonOptions, TestContext.CancellationToken))!.Version;

        Assert.AreEqual(1, v1);
        Assert.AreEqual(2, v2);

        var get = await client.GetAsync("/api/vault/icon-library", TestContext.CancellationToken);
        var got = await get.Content.ReadFromJsonAsync<IconLibraryResponse>(JsonOptions, TestContext.CancellationToken);
        Assert.AreEqual(blobB, got!.EncryptedPayload);
    }

    [TestMethod]
    public async Task Put_With_Stale_Version_Returns_Conflict()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        var (_, client) = await RegisterTestUserAsync(email);

        var blobA = Convert.ToBase64String([1, 2, 3]);
        await client.PutAsJsonAsync("/api/vault/icon-library",
            new IconLibraryUpdateRequest(blobA, 0), cancellationToken: TestContext.CancellationToken);

        // Now another "device" sends PUT with the stale version it saw
        var blobB = Convert.ToBase64String([4, 5, 6]);
        var stale = await client.PutAsJsonAsync("/api/vault/icon-library",
            new IconLibraryUpdateRequest(blobB, 0), cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.Conflict, stale.StatusCode);
    }

    [TestMethod]
    public async Task Library_Is_Per_User()
    {
        var (_, aliceClient) = await RegisterTestUserAsync($"alice-{Guid.NewGuid():N}@example.com");
        var (_, bobClient)   = await RegisterTestUserAsync($"bob-{Guid.NewGuid():N}@example.com");

        var aliceBlob = Convert.ToBase64String([10, 20, 30]);
        await aliceClient.PutAsJsonAsync("/api/vault/icon-library",
            new IconLibraryUpdateRequest(aliceBlob, 0), cancellationToken: TestContext.CancellationToken);

        // Bob's library should still be empty
        var bobResp = await bobClient.GetAsync("/api/vault/icon-library", TestContext.CancellationToken);
        var bobPayload = await bobResp.Content.ReadFromJsonAsync<IconLibraryResponse>(JsonOptions, TestContext.CancellationToken);
        Assert.IsNotNull(bobPayload);
        Assert.AreEqual(string.Empty, bobPayload.EncryptedPayload);
        Assert.AreEqual(0, bobPayload.Version);

        // Alice's library is unchanged
        var aliceResp = await aliceClient.GetAsync("/api/vault/icon-library", TestContext.CancellationToken);
        var alicePayload = await aliceResp.Content.ReadFromJsonAsync<IconLibraryResponse>(JsonOptions, TestContext.CancellationToken);
        Assert.IsNotNull(alicePayload);
        Assert.AreEqual(aliceBlob, alicePayload.EncryptedPayload);
    }

    [TestMethod]
    public async Task Put_Rejects_Oversized_Payload()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        var (_, client) = await RegisterTestUserAsync(email);

        // 2MB + 1 byte — just over the cap
        var oversized = new byte[2 * 1024 * 1024 + 1];
        var response = await client.PutAsJsonAsync("/api/vault/icon-library",
            new IconLibraryUpdateRequest(Convert.ToBase64String(oversized), 0),
            cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.BadRequest, response.StatusCode);
    }

    public TestContext TestContext { get; set; } = null!;
}
