using System.Security.Cryptography;
using Konscious.Security.Cryptography;

namespace PsTotp.Server.Application.Crypto;

public static class Argon2Kdf
{
    public static byte[] GenerateSalt(int length = 16)
    {
        return RandomNumberGenerator.GetBytes(length);
    }

    public static byte[] DeriveKey(byte[] password, byte[] salt, KdfConfig config)
    {
        ArgumentNullException.ThrowIfNull(password);
        ArgumentNullException.ThrowIfNull(salt);
        ArgumentNullException.ThrowIfNull(config);

        if (config.Algorithm != "argon2id")
            throw new ArgumentException($"Unsupported KDF algorithm: {config.Algorithm}");

        using var argon2 = new Argon2id(password);
        argon2.Salt = salt;
        argon2.MemorySize = config.MemoryMb * 1024; // Convert MB to KB
        argon2.Iterations = config.Iterations;
        argon2.DegreeOfParallelism = config.Parallelism;

        return argon2.GetBytes(config.HashLength);
    }

    public static byte[] HashRecoveryCode(string code, byte[] salt)
    {
        var codeBytes = System.Text.Encoding.UTF8.GetBytes(code);
        return DeriveKey(codeBytes, salt, KdfConfig.Default);
    }

    public static bool VerifyRecoveryCode(string code, byte[] salt, byte[] expectedHash)
    {
        var actualHash = HashRecoveryCode(code, salt);
        return CryptographicOperations.FixedTimeEquals(actualHash, expectedHash);
    }
}
