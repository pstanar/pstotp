using System.Security.Cryptography;

namespace PsTotp.Server.Application.Crypto;

public static class PasswordVerifier
{
    /// <summary>
    /// Verifies a client proof against the stored verifier using HMAC-SHA256.
    /// clientProof = HMAC-SHA256(PasswordVerifier, nonce || loginSessionId)
    /// </summary>
    public static bool VerifyClientProof(
        byte[] storedVerifier,
        byte[] nonce,
        Guid loginSessionId,
        byte[] clientProof)
    {
        var expectedProof = ComputeProof(storedVerifier, nonce, loginSessionId);
        return CryptographicOperations.FixedTimeEquals(expectedProof, clientProof);
    }

    /// <summary>
    /// Computes the expected proof for comparison.
    /// </summary>
    public static byte[] ComputeProof(byte[] verifier, byte[] nonce, Guid loginSessionId)
    {
        var sessionBytes = loginSessionId.ToByteArray();
        var message = new byte[nonce.Length + sessionBytes.Length];
        nonce.CopyTo(message, 0);
        sessionBytes.CopyTo(message, nonce.Length);

        return HMACSHA256.HashData(verifier, message);
    }

    /// <summary>
    /// Generates a random nonce for the login challenge.
    /// </summary>
    public static byte[] GenerateNonce(int length = 32)
    {
        return RandomNumberGenerator.GetBytes(length);
    }
}
