using System.Security.Cryptography;

namespace PsTotp.Server.Application.Crypto;

public static class AesGcmHelper
{
    public const int NonceLength = 12;
    private const int TagLength = 16;
    public const int KeyLength = 32;

    /// <summary>
    /// Encrypts plaintext using AES-256-GCM.
    /// Returns: nonce (12) || ciphertext || tag (16)
    /// </summary>
    public static byte[] Encrypt(byte[] key, byte[] plaintext, byte[]? associatedData = null)
    {
        ValidateKey(key);
        ArgumentNullException.ThrowIfNull(plaintext);

        var nonce = RandomNumberGenerator.GetBytes(NonceLength);
        var ciphertext = new byte[plaintext.Length];
        var tag = new byte[TagLength];

        using var aes = new AesGcm(key, TagLength);
        aes.Encrypt(nonce, plaintext, ciphertext, tag, associatedData);

        // Pack: nonce || ciphertext || tag
        var result = new byte[NonceLength + ciphertext.Length + TagLength];
        nonce.CopyTo(result, 0);
        ciphertext.CopyTo(result, NonceLength);
        tag.CopyTo(result, NonceLength + ciphertext.Length);

        return result;
    }

    /// <summary>
    /// Decrypts an AES-256-GCM payload: nonce (12) || ciphertext || tag (16)
    /// </summary>
    public static byte[] Decrypt(byte[] key, byte[] payload, byte[]? associatedData = null)
    {
        ValidateKey(key);
        ArgumentNullException.ThrowIfNull(payload);

        if (payload.Length < NonceLength + TagLength)
            throw new ArgumentException("Payload too short to contain nonce and tag.");

        var nonce = payload.AsSpan(0, NonceLength);
        var ciphertextLength = payload.Length - NonceLength - TagLength;
        var ciphertext = payload.AsSpan(NonceLength, ciphertextLength);
        var tag = payload.AsSpan(NonceLength + ciphertextLength, TagLength);

        var plaintext = new byte[ciphertextLength];

        using var aes = new AesGcm(key, TagLength);
        aes.Decrypt(nonce, ciphertext, tag, plaintext, associatedData);

        return plaintext;
    }

    private static void ValidateKey(byte[] key)
    {
        ArgumentNullException.ThrowIfNull(key);
        if (key.Length != KeyLength)
            throw new ArgumentException($"Key must be {KeyLength} bytes, got {key.Length}.");
    }
}
