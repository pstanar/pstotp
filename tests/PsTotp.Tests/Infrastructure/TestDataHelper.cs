using System.Security.Cryptography;
using System.Text.Json;
using PsTotp.Server.Application.Crypto;

namespace PsTotp.Tests.Infrastructure;

public static class TestDataHelper
{
    // A known 32-byte verifier used for all test users.
    // Tests can compute client proofs using this value.
    public static readonly byte[] TestVerifier = SHA256.HashData("test-password-verifier"u8);
    public static readonly string TestVerifierBase64 = Convert.ToBase64String(TestVerifier);

    // A second verifier for "new password" in password change tests
    public static readonly byte[] NewTestVerifier = SHA256.HashData("new-test-password-verifier"u8);
    public static readonly string NewTestVerifierBase64 = Convert.ToBase64String(NewTestVerifier);

    // Stable device public key for test devices (65 bytes, mimics ECDH P-256 uncompressed point)
    public static readonly string TestDevicePublicKey = Convert.ToBase64String(SHA256.HashData("test-device-key"u8).Concat(SHA256.HashData("test-device-key-2"u8)).Concat(new byte[] { 0x04 }).ToArray()[..65]);

    // A known salt for KDF config (must be defined before recovery code hashes)
    public static readonly byte[] TestSalt = SHA256.HashData("test-salt"u8)[..16];
    public static readonly string TestSaltBase64 = Convert.ToBase64String(TestSalt);

    // Known recovery codes and their Argon2id hashes for testing
    public static readonly string[] TestRecoveryCodes = ["TESTCODE01", "TESTCODE02", "TESTCODE03", "TESTCODE04", "TESTCODE05", "TESTCODE06", "TESTCODE07", "TESTCODE08"];
    public static readonly List<string> TestRecoveryCodeHashes = TestRecoveryCodes
        .Select(c => Convert.ToBase64String(Argon2Kdf.HashRecoveryCode(c, TestSalt)))
        .ToList();

    public static readonly string TestKdfConfigJson = JsonSerializer.Serialize(new
    {
        algorithm = "argon2id",
        memoryMb = 64,
        iterations = 3,
        parallelism = 4,
        salt = TestSaltBase64,
    });

    /// <summary>
    /// Creates a valid registration request body as a dictionary for JSON serialization.
    /// </summary>
    public static object CreateRegisterRequest(string? email = null)
    {
        email ??= $"test-{Guid.NewGuid():N}@example.com";

        // Dummy envelope: 12-byte nonce + 48-byte ciphertext (32 data + 16 tag)
        var dummyNonce = Convert.ToBase64String(RandomNumberGenerator.GetBytes(12));
        var dummyCiphertext = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48));

        return new
        {
            email,
            passwordVerifier = new
            {
                verifier = TestVerifierBase64,
                kdf = new
                {
                    algorithm = "argon2id",
                    memoryMb = 64,
                    iterations = 3,
                    parallelism = 4,
                    salt = TestSaltBase64,
                },
            },
            passwordEnvelope = new { ciphertext = dummyCiphertext, nonce = dummyNonce, version = 1 },
            device = new
            {
                deviceName = "Test Device",
                platform = "test",
                clientType = "mobile",
                devicePublicKey = TestDevicePublicKey,
            },
            deviceEnvelope = new { ciphertext = dummyCiphertext, nonce = dummyNonce, version = 1 },
            recovery = new
            {
                recoveryEnvelopeCiphertext = dummyCiphertext,
                recoveryEnvelopeNonce = dummyNonce,
                recoveryEnvelopeVersion = 1,
                recoveryCodeHashes = TestRecoveryCodeHashes,
            },
        };
    }

    /// <summary>
    /// Creates a valid login request body.
    /// </summary>
    public static object CreateLoginRequest(string email, string? deviceName = null, string? devicePublicKey = null)
    {
        // Default to the test device key for "Test Device" (matches registration), empty for new devices
        var key = devicePublicKey ?? (deviceName is null or "Test Device" ? TestDevicePublicKey : "");

        return new
        {
            email,
            device = new
            {
                deviceName = deviceName ?? "Test Device",
                platform = "test",
                clientType = "mobile",
                devicePublicKey = key,
            },
        };
    }

    /// <summary>
    /// Computes a valid client proof for the login/complete step.
    /// </summary>
    public static string ComputeClientProof(byte[] nonce, Guid sessionId)
    {
        return ComputeClientProofWith(TestVerifier, nonce, sessionId);
    }

    public static string ComputeClientProofWith(byte[] verifier, byte[] nonce, Guid sessionId)
    {
        var proof = PasswordVerifier.ComputeProof(verifier, nonce, sessionId);
        return Convert.ToBase64String(proof);
    }

    /// <summary>
    /// Creates a dummy encrypted vault entry payload (base64).
    /// </summary>
    public static string CreateVaultEntryPayload()
    {
        // nonce (12) + ciphertext (32) + tag (16) = 60 bytes
        return Convert.ToBase64String(RandomNumberGenerator.GetBytes(60));
    }
}
