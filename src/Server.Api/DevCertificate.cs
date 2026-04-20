using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

namespace PsTotp.Server.Api;

/// <summary>
/// Generates a self-signed certificate for development HTTPS that covers
/// localhost and all local network IPv4 addresses.
/// </summary>
public static class DevCertificate
{
    public static X509Certificate2 GetOrCreate(string dataDir)
    {
        var certPath = Path.Combine(dataDir, "dev-cert.pfx");

        if (File.Exists(certPath))
        {
            try
            {
                var existing = X509CertificateLoader.LoadPkcs12FromFile(certPath, null);
                if (existing.NotAfter > DateTime.UtcNow.AddDays(7))
                    return existing;
                existing.Dispose();
            }
            catch
            {
                // Cert is corrupted or unreadable — regenerate
            }
        }

        var cert = Generate();
        File.WriteAllBytes(certPath, cert.Export(X509ContentType.Pfx));
        return cert;
    }

    private static X509Certificate2 Generate()
    {
        var sanBuilder = new SubjectAlternativeNameBuilder();
        sanBuilder.AddDnsName("localhost");

        // Add all local IPv4 addresses
        foreach (var ip in GetLocalIpAddresses())
        {
            sanBuilder.AddIpAddress(ip);
        }

        using var key = RSA.Create(2048);
        var request = new CertificateRequest(
            "CN=PsTotp Development",
            key,
            HashAlgorithmName.SHA256,
            RSASignaturePadding.Pkcs1);

        request.CertificateExtensions.Add(
            new X509KeyUsageExtension(X509KeyUsageFlags.DigitalSignature | X509KeyUsageFlags.KeyEncipherment, false));
        request.CertificateExtensions.Add(
            new X509EnhancedKeyUsageExtension([new Oid("1.3.6.1.5.5.7.3.1")], false)); // Server auth
        request.CertificateExtensions.Add(sanBuilder.Build());

        var cert = request.CreateSelfSigned(DateTimeOffset.UtcNow, DateTimeOffset.UtcNow.AddYears(1));

        // Export and re-import so the private key is usable by Kestrel on Windows
        return X509CertificateLoader.LoadPkcs12(
            cert.Export(X509ContentType.Pfx),
            null,
            X509KeyStorageFlags.MachineKeySet | X509KeyStorageFlags.Exportable);
    }

    public static IEnumerable<IPAddress> GetLocalIpAddresses()
    {
        return NetworkInterface.GetAllNetworkInterfaces()
            .Where(n => n.OperationalStatus == OperationalStatus.Up
                        && n.NetworkInterfaceType != NetworkInterfaceType.Loopback)
            .SelectMany(n => n.GetIPProperties().UnicastAddresses)
            .Where(a => a.Address.AddressFamily == AddressFamily.InterNetwork)
            .Select(a => a.Address);
    }
}
