using System.Net;
using System.Net.Http.Json;
using PsTotp.Tests.Infrastructure;

namespace PsTotp.Tests.Api;

[TestClass]
public class RefreshTokenRotationTests : IntegrationTestBase
{
    [TestMethod]
    public async Task Refresh_Returns_New_Access_And_Refresh_Token()
    {
        // Register to get a refresh token (mobile clientType returns tokens in body)
        var email = $"test-{Guid.NewGuid():N}@example.com";
        await Client.PostAsJsonAsync("/api/auth/register", TestDataHelper.CreateRegisterRequest(email), cancellationToken: TestContext.CancellationToken);

        // Login to get tokens
        var loginResult = await LoginTestUserAsync(email);
        Assert.IsNotNull(loginResult.RefreshToken);

        // Refresh
        var response = await Client.PostAsJsonAsync("/api/auth/refresh", new
        {
            refreshToken = loginResult.RefreshToken,
        }, cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);
        var result = await response.Content.ReadFromJsonAsync<RefreshResult>(JsonOptions, TestContext.CancellationToken);
        Assert.IsNotNull(result);
        Assert.IsFalse(string.IsNullOrEmpty(result.AccessToken));
        Assert.IsFalse(string.IsNullOrEmpty(result.RefreshToken));
        Assert.AreNotEqual(loginResult.RefreshToken, result.RefreshToken);
    }

    [TestMethod]
    public async Task Refresh_Revokes_Previous_Token()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        await Client.PostAsJsonAsync("/api/auth/register", TestDataHelper.CreateRegisterRequest(email), cancellationToken: TestContext.CancellationToken);
        var loginResult = await LoginTestUserAsync(email);

        // First refresh succeeds
        var refresh1 = await Client.PostAsJsonAsync("/api/auth/refresh", new
        {
            refreshToken = loginResult.RefreshToken,
        }, cancellationToken: TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.OK, refresh1.StatusCode);

        // Second refresh with old token fails
        var refresh2 = await Client.PostAsJsonAsync("/api/auth/refresh", new
        {
            refreshToken = loginResult.RefreshToken,
        }, cancellationToken: TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.Unauthorized, refresh2.StatusCode);
    }

    [TestMethod]
    public async Task Refresh_Rejects_Invalid_Token()
    {
        var response = await Client.PostAsJsonAsync("/api/auth/refresh", new
        {
            refreshToken = Convert.ToBase64String(new byte[64]),
        }, cancellationToken: TestContext.CancellationToken);

        Assert.AreEqual(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [TestMethod]
    public async Task Logout_Revokes_Refresh_Token()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        await Client.PostAsJsonAsync("/api/auth/register", TestDataHelper.CreateRegisterRequest(email), cancellationToken: TestContext.CancellationToken);
        var loginResult = await LoginTestUserAsync(email);

        // Logout
        var logoutResponse = await Client.PostAsJsonAsync("/api/auth/logout", new
        {
            refreshToken = loginResult.RefreshToken,
        }, cancellationToken: TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.OK, logoutResponse.StatusCode);

        // Refresh with revoked token fails
        var refreshResponse = await Client.PostAsJsonAsync("/api/auth/refresh", new
        {
            refreshToken = loginResult.RefreshToken,
        }, cancellationToken: TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.Unauthorized, refreshResponse.StatusCode);
    }

    private sealed record RefreshResult(string? AccessToken, string? RefreshToken);

    public TestContext TestContext { get; set; } = null!;
}
