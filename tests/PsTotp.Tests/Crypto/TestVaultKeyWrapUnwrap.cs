using PsTotp.Server.Application.Crypto;

namespace PsTotp.Tests.Crypto;

[TestClass]
public class TestVaultKeyWrapUnwrap
{
    [TestMethod]
    public void WrapUnwrap_RoundTrips_VaultKey()
    {
        var wrappingKey = VaultCrypto.GenerateKey();
        var vaultKey = VaultCrypto.GenerateKey();

        var wrapped = VaultCrypto.WrapKey(wrappingKey, vaultKey);
        var unwrapped = VaultCrypto.UnwrapKey(wrappingKey, wrapped);

        CollectionAssert.AreEqual(vaultKey, unwrapped);
    }

    [TestMethod]
    public void WrapUnwrap_With_AssociatedData_RoundTrips()
    {
        var wrappingKey = VaultCrypto.GenerateKey();
        var vaultKey = VaultCrypto.GenerateKey();
        var userId = Guid.NewGuid();
        var ad = VaultCrypto.EnvelopeAssociatedData("password", userId);

        var wrapped = VaultCrypto.WrapKey(wrappingKey, vaultKey, ad);
        var unwrapped = VaultCrypto.UnwrapKey(wrappingKey, wrapped, ad);

        CollectionAssert.AreEqual(vaultKey, unwrapped);
    }

    [TestMethod]
    public void Unwrap_Fails_With_Wrong_Key()
    {
        var wrappingKey = VaultCrypto.GenerateKey();
        var wrongKey = VaultCrypto.GenerateKey();
        var vaultKey = VaultCrypto.GenerateKey();

        var wrapped = VaultCrypto.WrapKey(wrappingKey, vaultKey);

        Assert.ThrowsExactly<System.Security.Cryptography.AuthenticationTagMismatchException>(
            () => VaultCrypto.UnwrapKey(wrongKey, wrapped));
    }

    [TestMethod]
    public void Unwrap_Fails_With_Wrong_AssociatedData()
    {
        var wrappingKey = VaultCrypto.GenerateKey();
        var vaultKey = VaultCrypto.GenerateKey();
        var userId = Guid.NewGuid();
        var correctAd = VaultCrypto.EnvelopeAssociatedData("password", userId);
        var wrongAd = VaultCrypto.EnvelopeAssociatedData("device", userId);

        var wrapped = VaultCrypto.WrapKey(wrappingKey, vaultKey, correctAd);

        Assert.ThrowsExactly<System.Security.Cryptography.AuthenticationTagMismatchException>(
            () => VaultCrypto.UnwrapKey(wrappingKey, wrapped, wrongAd));
    }

    [TestMethod]
    public void Unwrap_Fails_With_Tampered_Payload()
    {
        var wrappingKey = VaultCrypto.GenerateKey();
        var vaultKey = VaultCrypto.GenerateKey();

        var wrapped = VaultCrypto.WrapKey(wrappingKey, vaultKey);
        wrapped[wrapped.Length / 2] ^= 0xFF; // Flip a byte

        Assert.ThrowsExactly<System.Security.Cryptography.AuthenticationTagMismatchException>(
            () => VaultCrypto.UnwrapKey(wrappingKey, wrapped));
    }

    [TestMethod]
    public void Wrap_Produces_Different_Ciphertext_Each_Time()
    {
        var wrappingKey = VaultCrypto.GenerateKey();
        var vaultKey = VaultCrypto.GenerateKey();

        var wrapped1 = VaultCrypto.WrapKey(wrappingKey, vaultKey);
        var wrapped2 = VaultCrypto.WrapKey(wrappingKey, vaultKey);

        CollectionAssert.AreNotEqual(wrapped1, wrapped2,
            "Each wrap must use a unique nonce, producing different ciphertext");
    }

    [TestMethod]
    public void PasswordEnvelope_FullFlow()
    {
        // Simulate the full password envelope flow
        var password = "user-password"u8.ToArray();
        var salt = Argon2Kdf.GenerateSalt();
        var vaultKey = VaultCrypto.GenerateKey();
        var userId = Guid.NewGuid();

        // Client-side: derive keys
        var authKey = Argon2Kdf.DeriveKey(password, salt, KdfConfig.Default);
        var envelopeKey = HkdfHelper.DerivePasswordEnvelopeKey(authKey);

        // Client-side: wrap VaultKey
        var ad = VaultCrypto.EnvelopeAssociatedData("password", userId);
        var wrapped = VaultCrypto.WrapKey(envelopeKey, vaultKey, ad);

        // Later: client re-derives the same envelope key and unwraps
        var authKey2 = Argon2Kdf.DeriveKey(password, salt, KdfConfig.Default);
        var envelopeKey2 = HkdfHelper.DerivePasswordEnvelopeKey(authKey2);
        var unwrapped = VaultCrypto.UnwrapKey(envelopeKey2, wrapped, ad);

        CollectionAssert.AreEqual(vaultKey, unwrapped);
    }

    [TestMethod]
    public void DeviceEnvelope_FullFlow()
    {
        var vaultKey = VaultCrypto.GenerateKey();
        var deviceKey = VaultCrypto.GenerateKey(); // In practice, from platform keystore
        var userId = Guid.NewGuid();

        var ad = VaultCrypto.EnvelopeAssociatedData("device", userId);
        var wrapped = VaultCrypto.WrapKey(deviceKey, vaultKey, ad);
        var unwrapped = VaultCrypto.UnwrapKey(deviceKey, wrapped, ad);

        CollectionAssert.AreEqual(vaultKey, unwrapped);
    }

    [TestMethod]
    public void RecoveryEnvelope_FullFlow()
    {
        var vaultKey = VaultCrypto.GenerateKey();
        var recoveryKey = VaultCrypto.GenerateKey();
        var recoverySeed = VaultCrypto.GenerateKey();
        var userId = Guid.NewGuid();

        // Wrap VaultKey with RecoveryKey
        var recoveryAd = VaultCrypto.EnvelopeAssociatedData("recovery", userId);
        var recoveryEnvelope = VaultCrypto.WrapKey(recoveryKey, vaultKey, recoveryAd);

        // Wrap RecoveryKey with Recovery Unlock Key (derived from seed)
        var recoveryUnlockKey = HkdfHelper.DeriveRecoveryUnlockKey(recoverySeed);
        var wrappedRecoveryKey = VaultCrypto.WrapKey(recoveryUnlockKey, recoveryKey);

        // Recovery: derive unlock key from seed, unwrap chain
        var recoveryUnlockKey2 = HkdfHelper.DeriveRecoveryUnlockKey(recoverySeed);
        var recoveredRecoveryKey = VaultCrypto.UnwrapKey(recoveryUnlockKey2, wrappedRecoveryKey);
        var recoveredVaultKey = VaultCrypto.UnwrapKey(recoveredRecoveryKey, recoveryEnvelope, recoveryAd);

        CollectionAssert.AreEqual(vaultKey, recoveredVaultKey);
    }
}
