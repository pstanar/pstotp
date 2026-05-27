using Microsoft.Extensions.Configuration;
using PsTotp.Server.Api;

namespace PsTotp.Tests.Security;

/// <summary>
/// Pure-function tests for the AllowedOrigins / listen-URL resolver in
/// <see cref="AuthConstants"/>. The behaviour covered here is the
/// difference between "operator explicitly set AllowedOrigins" (use as-is)
/// and "default fallback" (union with the resolved listen URLs so non-
/// default-port deployments don't silently break the SPA).
/// </summary>
[TestClass]
public class AllowedOriginsResolutionTests
{
    private static IConfiguration BuildConfig(Dictionary<string, string?> data) =>
        new ConfigurationBuilder().AddInMemoryCollection(data).Build();

    [TestMethod]
    public void Explicit_AllowedOrigins_Wins_Over_Listen_Urls()
    {
        var config = BuildConfig(new()
        {
            ["AllowedOrigins"] = "https://totp.example.com",
            ["Urls"] = "http://localhost:5245",
        });

        var resolved = AuthConstants.ResolveAllowedOrigins(config, isDevelopment: false);

        Assert.AreEqual("https://totp.example.com", resolved);
    }

    [TestMethod]
    public void Default_Resolution_Unions_Listen_Urls_For_Custom_Port()
    {
        var config = BuildConfig(new()
        {
            ["Urls"] = "http://localhost:5245",
        });

        var resolved = AuthConstants.ResolveAllowedOrigins(config, isDevelopment: false);
        var parts = resolved.Split(';');

        // Production defaults (5000/5001) AND the listen URL on 5245.
        CollectionAssert.Contains(parts, "http://localhost:5000");
        CollectionAssert.Contains(parts, "https://localhost:5001");
        CollectionAssert.Contains(parts, "http://localhost:5245");
    }

    [TestMethod]
    public void Default_Resolution_Unions_Listen_Urls_In_Development()
    {
        var config = BuildConfig(new()
        {
            ["Urls"] = "http://localhost:5245",
        });

        var resolved = AuthConstants.ResolveAllowedOrigins(config, isDevelopment: true);
        var parts = resolved.Split(';');

        CollectionAssert.Contains(parts, "http://localhost:5173");
        CollectionAssert.Contains(parts, "http://localhost:5245");
    }

    [TestMethod]
    public void Default_Resolution_With_No_Listen_Urls_Falls_Back_To_Defaults()
    {
        var config = BuildConfig([]);

        var resolved = AuthConstants.ResolveAllowedOrigins(config, isDevelopment: false);

        Assert.AreEqual(AuthConstants.DefaultProductionOrigin, resolved);
    }

    [TestMethod]
    public void Listen_Url_Wildcard_Hosts_Normalise_To_Localhost()
    {
        var config = BuildConfig(new()
        {
            ["Urls"] = "http://0.0.0.0:5245;http://[::]:5246;http://*:5247;http://+:5248",
        });

        var origins = AuthConstants.ResolveListenOrigins(config);

        CollectionAssert.Contains(origins.ToArray(), "http://localhost:5245");
        CollectionAssert.Contains(origins.ToArray(), "http://localhost:5246");
        CollectionAssert.Contains(origins.ToArray(), "http://localhost:5247");
        CollectionAssert.Contains(origins.ToArray(), "http://localhost:5248");
    }

    [TestMethod]
    public void Listen_Origins_Includes_Kestrel_Endpoints()
    {
        var config = BuildConfig(new()
        {
            ["Kestrel:Endpoints:Http:Url"] = "http://localhost:6000",
            ["Kestrel:Endpoints:Https:Url"] = "https://localhost:6001",
        });

        var origins = AuthConstants.ResolveListenOrigins(config);

        CollectionAssert.Contains(origins.ToArray(), "http://localhost:6000");
        CollectionAssert.Contains(origins.ToArray(), "https://localhost:6001");
    }

    [TestMethod]
    public void Listen_Origins_Includes_Multiple_Urls_From_Single_Config_Value()
    {
        var config = BuildConfig(new()
        {
            ["Urls"] = "http://localhost:5000;https://localhost:5001",
        });

        var origins = AuthConstants.ResolveListenOrigins(config);

        Assert.AreEqual(2, origins.Count);
        CollectionAssert.Contains(origins.ToArray(), "http://localhost:5000");
        CollectionAssert.Contains(origins.ToArray(), "https://localhost:5001");
    }

    [TestMethod]
    public void Listen_Origins_Ignores_Malformed_Urls()
    {
        var config = BuildConfig(new()
        {
            ["Urls"] = "not-a-url;http://localhost:5000",
        });

        var origins = AuthConstants.ResolveListenOrigins(config);

        Assert.AreEqual(1, origins.Count);
        Assert.AreEqual("http://localhost:5000", origins[0]);
    }
}
