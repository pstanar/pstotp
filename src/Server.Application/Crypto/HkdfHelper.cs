using System.Security.Cryptography;
using System.Text;

namespace PsTotp.Server.Application.Crypto;

public static class HkdfHelper
{
    public const string AuthVerifierContext = "auth-verifier-v1";
    private const string PasswordEnvelopeContext = "vault-password-envelope-v1";
    private const string RecoveryUnlockContext = "totp-vault-recovery-unlock-v1";

    private static byte[] DeriveKey(byte[] inputKeyMaterial, string context, int outputLength = 32)
    {
        ArgumentNullException.ThrowIfNull(inputKeyMaterial);
        ArgumentException.ThrowIfNullOrEmpty(context);

        var info = Encoding.UTF8.GetBytes(context);
        return HKDF.DeriveKey(HashAlgorithmName.SHA256, inputKeyMaterial, outputLength, info: info);
    }

    public static byte[] DeriveVerifier(byte[] passwordAuthKey)
    {
        return DeriveKey(passwordAuthKey, AuthVerifierContext);
    }

    public static byte[] DerivePasswordEnvelopeKey(byte[] passwordAuthKey)
    {
        return DeriveKey(passwordAuthKey, PasswordEnvelopeContext);
    }

    public static byte[] DeriveRecoveryUnlockKey(byte[] recoverySeed)
    {
        return DeriveKey(recoverySeed, RecoveryUnlockContext);
    }
}
