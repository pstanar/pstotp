using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace PsTotp.Server.Application.Crypto;

public static class VaultCrypto
{
    /// <summary>
    /// Generates a random 256-bit key (for VaultKey, RecoveryKey, etc.)
    /// </summary>
    public static byte[] GenerateKey()
    {
        return RandomNumberGenerator.GetBytes(AesGcmHelper.KeyLength);
    }

    /// <summary>
    /// Wraps (encrypts) a key with another key using AES-256-GCM.
    /// Associated data provides domain separation.
    /// </summary>
    public static byte[] WrapKey(byte[] wrappingKey, byte[] keyToWrap, byte[]? associatedData = null)
    {
        return AesGcmHelper.Encrypt(wrappingKey, keyToWrap, associatedData);
    }

    /// <summary>
    /// Unwraps (decrypts) a key with another key using AES-256-GCM.
    /// </summary>
    public static byte[] UnwrapKey(byte[] wrappingKey, byte[] wrappedPayload, byte[]? associatedData = null)
    {
        return AesGcmHelper.Decrypt(wrappingKey, wrappedPayload, associatedData);
    }

    /// <summary>
    /// Encrypts a vault entry plaintext object with VaultKey.
    /// </summary>
    public static byte[] EncryptEntry(byte[] vaultKey, VaultEntryPlaintext entry, Guid entryId)
    {
        var json = JsonSerializer.SerializeToUtf8Bytes(entry);
        var associatedData = Encoding.UTF8.GetBytes(entryId.ToString());
        return AesGcmHelper.Encrypt(vaultKey, json, associatedData);
    }

    /// <summary>
    /// Decrypts a vault entry payload back to plaintext.
    /// </summary>
    public static VaultEntryPlaintext DecryptEntry(byte[] vaultKey, byte[] payload, Guid entryId)
    {
        var associatedData = Encoding.UTF8.GetBytes(entryId.ToString());
        var json = AesGcmHelper.Decrypt(vaultKey, payload, associatedData);
        return JsonSerializer.Deserialize<VaultEntryPlaintext>(json)
               ?? throw new InvalidOperationException("Failed to deserialize vault entry.");
    }

    /// <summary>
    /// Builds the associated data for a key envelope.
    /// </summary>
    public static byte[] EnvelopeAssociatedData(string envelopeType, Guid userId)
    {
        return Encoding.UTF8.GetBytes($"{envelopeType}:{userId}");
    }
}

public sealed record VaultEntryPlaintext
{
    public required string Issuer { get; init; }
    public required string AccountName { get; init; }
    public required string Secret { get; init; }
    public string Algorithm { get; init; } = "SHA1";
    public int Digits { get; init; } = 6;
    public int Period { get; init; } = 30;
}
