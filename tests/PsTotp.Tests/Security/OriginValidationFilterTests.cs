using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using PsTotp.Server.Api;
using PsTotp.Server.Api.Filters;

namespace PsTotp.Tests.Security;

/// <summary>
/// Direct unit tests for <see cref="OriginValidationFilter"/>. Exercises the
/// branches that matter: state-changing method gate, Bearer bypass, cookie-
/// auth gate, Origin/Referer matching, and the JSON 403 body shape (the
/// last is the one that turns a bare "Import failed" toast into something
/// the SPA can show a sensible message for).
/// </summary>
[TestClass]
public class OriginValidationFilterTests
{
    private static OriginValidationFilter BuildFilter(string? allowedOrigins = null)
    {
        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["AllowedOrigins"] = allowedOrigins ?? "http://localhost:5245",
            }).Build();
        var env = new TestHostEnvironment();
        return new OriginValidationFilter(config, env);
    }

    private static TestContext BuildContext(
        string method,
        string? origin = null,
        string? referer = null,
        string? authorization = null,
        bool withAccessCookie = true)
    {
        var httpContext = new DefaultHttpContext();
        httpContext.Request.Method = method;

        if (origin is not null)
            httpContext.Request.Headers.Origin = origin;
        if (referer is not null)
            httpContext.Request.Headers.Referer = referer;
        if (authorization is not null)
            httpContext.Request.Headers.Authorization = authorization;
        if (withAccessCookie)
            httpContext.Request.Headers["Cookie"] = $"{AuthConstants.AccessTokenCookieName}=dummy";

        return new TestContext(httpContext);
    }

    private static async Task<(bool Continued, IResult? Rejected)> InvokeAsync(
        OriginValidationFilter filter,
        EndpointFilterInvocationContext context)
    {
        var continued = false;
        EndpointFilterDelegate next = _ =>
        {
            continued = true;
            return ValueTask.FromResult<object?>(Results.Ok());
        };

        var result = await filter.InvokeAsync(context, next);
        if (continued) return (true, null);
        return (false, result as IResult);
    }

    [TestMethod]
    public async Task Get_Requests_Bypass_The_Filter()
    {
        var filter = BuildFilter();
        var context = BuildContext("GET", origin: "https://attacker.example");

        var (continued, _) = await InvokeAsync(filter, context);

        Assert.IsTrue(continued, "GET should pass through without origin checks");
    }

    [TestMethod]
    public async Task Bearer_Authenticated_Requests_Bypass_The_Filter()
    {
        var filter = BuildFilter();
        var context = BuildContext("PUT",
            origin: "https://attacker.example",
            authorization: "Bearer some-token-here",
            withAccessCookie: false);

        var (continued, _) = await InvokeAsync(filter, context);

        Assert.IsTrue(continued, "Bearer-authed requests skip cookie-CSRF defence");
    }

    [TestMethod]
    public async Task Cookie_Authed_Put_With_Matching_Origin_Passes()
    {
        var filter = BuildFilter("http://localhost:5245");
        var context = BuildContext("PUT", origin: "http://localhost:5245");

        var (continued, _) = await InvokeAsync(filter, context);

        Assert.IsTrue(continued);
    }

    [TestMethod]
    public async Task Cookie_Authed_Put_With_Mismatched_Origin_Returns_403_With_Json_Body()
    {
        var filter = BuildFilter("http://localhost:5245");
        var context = BuildContext("PUT", origin: "http://localhost:5173");

        var (continued, result) = await InvokeAsync(filter, context);

        Assert.IsFalse(continued);
        var body = await ExecuteAndReadAsync(result!);
        Assert.AreEqual(HttpStatusCode.Forbidden, body.StatusCode);
        Assert.AreEqual(AuthConstants.ErrorOriginNotAllowed, body.Payload.GetProperty("error").GetString());
        Assert.AreEqual("http://localhost:5173", body.Payload.GetProperty("origin").GetString());
    }

    [TestMethod]
    public async Task Cookie_Authed_Put_With_No_Origin_But_Matching_Referer_Passes()
    {
        var filter = BuildFilter("http://localhost:5245");
        var context = BuildContext("PUT",
            origin: null,
            referer: "http://localhost:5245/settings");

        var (continued, _) = await InvokeAsync(filter, context);

        Assert.IsTrue(continued);
    }

    [TestMethod]
    public async Task Cookie_Authed_Put_With_No_Origin_And_No_Referer_Returns_403_With_Null_Origin()
    {
        var filter = BuildFilter("http://localhost:5245");
        var context = BuildContext("PUT", origin: null, referer: null);

        var (continued, result) = await InvokeAsync(filter, context);

        Assert.IsFalse(continued);
        var body = await ExecuteAndReadAsync(result!);
        Assert.AreEqual(HttpStatusCode.Forbidden, body.StatusCode);
        Assert.AreEqual(AuthConstants.ErrorOriginNotAllowed, body.Payload.GetProperty("error").GetString());
        Assert.AreEqual(JsonValueKind.Null, body.Payload.GetProperty("origin").ValueKind);
    }

    [TestMethod]
    public async Task Cookie_Authed_Put_With_No_Origin_And_Mismatched_Referer_Returns_403_With_Referer_Origin()
    {
        var filter = BuildFilter("http://localhost:5245");
        var context = BuildContext("PUT",
            origin: null,
            referer: "https://attacker.example/page");

        var (continued, result) = await InvokeAsync(filter, context);

        Assert.IsFalse(continued);
        var body = await ExecuteAndReadAsync(result!);
        Assert.AreEqual(HttpStatusCode.Forbidden, body.StatusCode);
        Assert.AreEqual("https://attacker.example", body.Payload.GetProperty("origin").GetString());
    }

    [TestMethod]
    public async Task Unauthenticated_Put_With_No_Cookie_Bypasses_Origin_Check()
    {
        // Filter only kicks in for cookie-authed requests. Unauthenticated
        // requests fall through to the [Authorize] gate, which 401s them.
        var filter = BuildFilter();
        var context = BuildContext("PUT",
            origin: "https://attacker.example",
            withAccessCookie: false);

        var (continued, _) = await InvokeAsync(filter, context);

        Assert.IsTrue(continued);
    }

    // --- helpers ---

    private sealed class TestContext(HttpContext httpContext) : EndpointFilterInvocationContext
    {
        public override HttpContext HttpContext { get; } = httpContext;
        public override IList<object?> Arguments { get; } = [];
        public override T GetArgument<T>(int index) => throw new NotSupportedException();
    }

    private sealed class TestHostEnvironment : IHostEnvironment
    {
        public string EnvironmentName { get; set; } = "Testing";
        public string ApplicationName { get; set; } = "PsTotp.Tests";
        public string ContentRootPath { get; set; } = "";
        public Microsoft.Extensions.FileProviders.IFileProvider ContentRootFileProvider { get; set; } = null!;
    }

    private sealed record RejectionBody(HttpStatusCode StatusCode, JsonElement Payload);

    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    private static async Task<RejectionBody> ExecuteAndReadAsync(IResult result)
    {
        var services = new ServiceCollection().AddLogging().BuildServiceProvider();
        var httpContext = new DefaultHttpContext { RequestServices = services };
        var stream = new MemoryStream();
        httpContext.Response.Body = stream;

        await result.ExecuteAsync(httpContext);
        stream.Seek(0, SeekOrigin.Begin);
        var payload = await JsonSerializer.DeserializeAsync<JsonElement>(stream, JsonOpts);
        return new RejectionBody((HttpStatusCode)httpContext.Response.StatusCode, payload);
    }
}
