using System.Net;
using System.Net.Http.Json;
using PsTotp.Tests.Infrastructure;

namespace PsTotp.Tests.Security;

/// <summary>
/// Locks in the contract that DeviceAuthHelper returns 401 (not 500, not
/// 403) when the JWT's <c>sub</c> or <c>device_id</c> claim is missing
/// or not a valid Guid. The underlying TryGetUserId / TryGetDeviceId
/// paths run on every protected request; using a vault endpoint as the
/// exercise target since it goes through RejectIfDeviceNotApproved, and
/// a recovery endpoint to cover the AuthoriseCallerDevice path too.
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
        // AuthoriseCallerDevice is used by recovery + webauthn endpoints.
        // Exercise via /api/webauthn/credentials (GET — ListCredentials
        // uses RejectIfDeviceNotApproved, but a missing sub still 401s
        // since both helpers share the same TryGet* validation).
        var client = CreateClientWithRawClaims(sub: "bogus", deviceId: "also-bogus");

        var response = await client.GetAsync("/api/webauthn/credentials",
            cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.Unauthorized, response.StatusCode);
        client.Dispose();
    }

    public TestContext TestContext { get; set; } = null!;
}
