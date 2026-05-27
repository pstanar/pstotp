using System.Net;
using System.Net.Http.Json;
using PsTotp.Tests.Infrastructure;

namespace PsTotp.Tests.Security;

/// <summary>
/// Locks in the contract that the auth pipeline returns 401 (not 500, not
/// 403) when the JWT's <c>sub</c> or <c>device_id</c> claim is missing
/// or not a valid Guid. The primary defence is the
/// <c>JwtBearerEvents.OnTokenValidated</c> hook in
/// <c>AppBuilder.ConfigureAuthentication</c>, which fails token validation
/// before any endpoint runs; DeviceAuthHelper's TryGet* paths are a
/// secondary defence-in-depth check. Exercised against both a vault
/// endpoint (RejectIfDeviceNotApproved path) and a webauthn endpoint
/// (AuthoriseCallerDevice path) to confirm the contract holds across the
/// protected route group.
/// </summary>
[TestClass]
public class MalformedClaimRejectionTests : IntegrationTestBase
{
    [TestMethod]
    public async Task Missing_Sub_Claim_Returns_401()
    {
        var client = CreateClientWithRawClaims(sub: null, deviceId: Guid.NewGuid().ToString());

        var response = await client.PostAsJsonAsync("/api/vault/reorder",
            new { entryIds = new[] { Guid.NewGuid().ToString() } },
            cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.Unauthorized, response.StatusCode);
        client.Dispose();
    }

    [TestMethod]
    public async Task Malformed_Sub_Claim_Returns_401()
    {
        var client = CreateClientWithRawClaims(sub: "not-a-guid", deviceId: Guid.NewGuid().ToString());

        var response = await client.PostAsJsonAsync("/api/vault/reorder",
            new { entryIds = new[] { Guid.NewGuid().ToString() } },
            cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.Unauthorized, response.StatusCode);
        client.Dispose();
    }

    [TestMethod]
    public async Task Missing_DeviceId_Claim_Returns_401()
    {
        var client = CreateClientWithRawClaims(sub: Guid.NewGuid().ToString(), deviceId: null);

        var response = await client.PostAsJsonAsync("/api/vault/reorder",
            new { entryIds = new[] { Guid.NewGuid().ToString() } },
            cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.Unauthorized, response.StatusCode);
        client.Dispose();
    }

    [TestMethod]
    public async Task Malformed_DeviceId_Claim_Returns_401()
    {
        var client = CreateClientWithRawClaims(sub: Guid.NewGuid().ToString(), deviceId: "bogus");

        var response = await client.PostAsJsonAsync("/api/vault/reorder",
            new { entryIds = new[] { Guid.NewGuid().ToString() } },
            cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.Unauthorized, response.StatusCode);
        client.Dispose();
    }

    [TestMethod]
    public async Task Malformed_Claims_Return_401_On_AuthoriseCallerDevice_Path()
    {
        // Hit a different protected endpoint to confirm the 401 contract
        // holds across the whole protected route group, not just for one
        // helper. The JWT validator catches malformed claims before
        // routing, so every protected path benefits from the same
        // guarantee.
        var client = CreateClientWithRawClaims(sub: "bogus", deviceId: "also-bogus");

        var response = await client.GetAsync("/api/webauthn/credentials",
            cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.Unauthorized, response.StatusCode);
        client.Dispose();
    }

    public TestContext TestContext { get; set; } = null!;
}
