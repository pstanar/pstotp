using System.Net;
using System.Net.Sockets;

namespace PsTotp.Server.Api.EndPoints;

/// <summary>
/// Authenticated image-fetch proxy so the web client can retrieve icons from
/// arbitrary URLs without being blocked by browser CORS. Includes SSRF
/// protections: http(s) only, resolves hostnames and rejects any resolution
/// to a private/loopback/link-local/reserved IP, size-limits the response,
/// and requires Content-Type: image/*.
/// </summary>
public static class IconProxyEndpoints
{
    public const string HttpClientName = "icon-proxy";
    private const int MaxResponseBytes = 2 * 1024 * 1024; // 2 MB
    private const int MaxRedirects = 5;

    public static async Task<IResult> ProxyIcon(
        string url,
        IHttpClientFactory httpClientFactory,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(url))
            return Results.BadRequest(new { Error = "url parameter is required" });

        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri))
            return Results.BadRequest(new { Error = "Invalid URL" });

        var client = httpClientFactory.CreateClient(HttpClientName);

        // Follow redirects manually (auto-redirect is disabled on the client so
        // we can re-validate each hop). Each Uri is validated before the request.
        HttpResponseMessage? response = null;
        try
        {
            for (var hop = 0; hop <= MaxRedirects; hop++)
            {
                var validationError = await ValidateTargetAsync(uri, ct);
                if (validationError is not null)
                    return validationError;

                response?.Dispose();
                response = await client.GetAsync(uri, HttpCompletionOption.ResponseHeadersRead, ct);

                if ((int)response.StatusCode is >= 300 and < 400 && response.Headers.Location is not null)
                {
                    if (hop == MaxRedirects)
                        return Results.BadRequest(new { Error = "Too many redirects" });

                    var next = response.Headers.Location.IsAbsoluteUri
                        ? response.Headers.Location
                        : new Uri(uri, response.Headers.Location);
                    uri = next;
                    continue;
                }

                break;
            }

            if (response is null)
                return Results.BadRequest(new { Error = "Fetch failed" });

            if (!response.IsSuccessStatusCode)
                return Results.StatusCode((int)response.StatusCode);

            var contentType = response.Content.Headers.ContentType?.MediaType;
            if (string.IsNullOrEmpty(contentType) ||
                !contentType.StartsWith("image/", StringComparison.OrdinalIgnoreCase))
                return Results.BadRequest(new { Error = "Response is not an image" });

            if (response.Content.Headers.ContentLength is > MaxResponseBytes)
                return Results.BadRequest(new { Error = "Image exceeds size limit" });

            // Stream and enforce the size cap, even if Content-Length was absent/misleading
            await using var source = await response.Content.ReadAsStreamAsync(ct);
            using var ms = new MemoryStream();
            var buffer = new byte[81920];
            var total = 0;
            while (true)
            {
                var read = await source.ReadAsync(buffer, ct);
                if (read == 0) break;
                total += read;
                if (total > MaxResponseBytes)
                    return Results.BadRequest(new { Error = "Image exceeds size limit" });
                await ms.WriteAsync(buffer.AsMemory(0, read), ct);
            }

            return Results.File(ms.ToArray(), contentType);
        }
        catch (TaskCanceledException)
        {
            return Results.BadRequest(new { Error = "Fetch timed out" });
        }
        catch (HttpRequestException)
        {
            return Results.BadRequest(new { Error = "Fetch failed" });
        }
        finally
        {
            response?.Dispose();
        }
    }

    /// <summary>
    /// Validates that the URL is eligible for fetch — http/https scheme and all
    /// resolved IPs are public. Returns null when OK; otherwise an error result.
    /// </summary>
    private static async Task<IResult?> ValidateTargetAsync(Uri target, CancellationToken ct)
    {
        if (target.Scheme != Uri.UriSchemeHttp && target.Scheme != Uri.UriSchemeHttps)
            return Results.BadRequest(new { Error = "Only http/https URLs are supported" });

        // Resolve the hostname and reject if any resolved IP is in a
        // private/loopback/link-local/reserved range. Note there is still a
        // small TOCTOU window against DNS rebinding between check and connect.
        try
        {
            var addresses = await Dns.GetHostAddressesAsync(target.Host, ct);
            if (addresses.Length == 0 || !addresses.All(IsPublicIp))
                return Results.BadRequest(new { Error = "Host is not a valid public address" });
        }
        catch (SocketException)
        {
            return Results.BadRequest(new { Error = "Could not resolve host" });
        }

        return null;
    }

    /// <summary>Returns true if the IP is a publicly routable unicast address.</summary>
    private static bool IsPublicIp(IPAddress ip)
    {
        if (IPAddress.IsLoopback(ip)) return false;
        if (ip.IsIPv6LinkLocal || ip.IsIPv6SiteLocal || ip.IsIPv6Multicast) return false;

        var bytes = ip.GetAddressBytes();

        if (ip.AddressFamily == AddressFamily.InterNetwork && bytes.Length == 4)
        {
            // 0.0.0.0/8         "this network"
            if (bytes[0] == 0) return false;
            // 10.0.0.0/8        private
            if (bytes[0] == 10) return false;
            // 100.64.0.0/10     CGNAT
            if (bytes[0] == 100 && (bytes[1] & 0xC0) == 64) return false;
            // 127.0.0.0/8       loopback
            if (bytes[0] == 127) return false;
            // 169.254.0.0/16    link-local (includes cloud metadata 169.254.169.254)
            if (bytes[0] == 169 && bytes[1] == 254) return false;
            // 172.16.0.0/12     private
            if (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] < 32) return false;
            // 192.0.0.0/24      IETF protocol assignments
            if (bytes[0] == 192 && bytes[1] == 0 && bytes[2] == 0) return false;
            // 192.168.0.0/16    private
            if (bytes[0] == 192 && bytes[1] == 168) return false;
            // 198.18.0.0/15     benchmarking
            if (bytes[0] == 198 && (bytes[1] & 0xFE) == 18) return false;
            // 224.0.0.0/4       multicast
            if (bytes[0] >= 224 && bytes[0] < 240) return false;
            // 240.0.0.0/4       reserved
            if (bytes[0] >= 240) return false;
        }
        else if (ip.AddressFamily == AddressFamily.InterNetworkV6)
        {
            // IPv6 unique local fc00::/7
            if ((bytes[0] & 0xFE) == 0xFC) return false;
            // IPv4-mapped IPv6: recurse on the embedded IPv4 address
            if (ip.IsIPv4MappedToIPv6) return IsPublicIp(ip.MapToIPv4());
        }

        return true;
    }
}
