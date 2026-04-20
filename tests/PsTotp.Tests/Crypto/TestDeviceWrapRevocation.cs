using PsTotp.Server.Application.Crypto;

namespace PsTotp.Tests.Crypto;

[TestClass]
public class TestDeviceWrapRevocation
{
    [TestMethod]
    public void Each_Device_Gets_Independent_Envelope()
    {
        var vaultKey = VaultCrypto.GenerateKey();
        var userId = Guid.NewGuid();
        var device1Key = VaultCrypto.GenerateKey();
        var device2Key = VaultCrypto.GenerateKey();
        var ad = VaultCrypto.EnvelopeAssociatedData("device", userId);

        var envelope1 = VaultCrypto.WrapKey(device1Key, vaultKey, ad);
        var envelope2 = VaultCrypto.WrapKey(device2Key, vaultKey, ad);

        // Both envelopes unwrap to the same VaultKey
        var unwrapped1 = VaultCrypto.UnwrapKey(device1Key, envelope1, ad);
        var unwrapped2 = VaultCrypto.UnwrapKey(device2Key, envelope2, ad);

        CollectionAssert.AreEqual(vaultKey, unwrapped1);
        CollectionAssert.AreEqual(vaultKey, unwrapped2);
    }

    [TestMethod]
    public void Revoked_Device_Key_Cannot_Unwrap_Other_Device_Envelope()
    {
        var vaultKey = VaultCrypto.GenerateKey();
        var userId = Guid.NewGuid();
        var device1Key = VaultCrypto.GenerateKey();
        var device2Key = VaultCrypto.GenerateKey();
        var ad = VaultCrypto.EnvelopeAssociatedData("device", userId);

        var envelope2 = VaultCrypto.WrapKey(device2Key, vaultKey, ad);

        // Device 1's key cannot unwrap device 2's envelope
        Assert.ThrowsExactly<System.Security.Cryptography.AuthenticationTagMismatchException>(
            () => VaultCrypto.UnwrapKey(device1Key, envelope2, ad));
    }

    [TestMethod]
    public void Revoking_Device_Does_Not_Affect_Other_Envelopes()
    {
        var vaultKey = VaultCrypto.GenerateKey();
        var userId = Guid.NewGuid();
        var device1Key = VaultCrypto.GenerateKey();
        var device2Key = VaultCrypto.GenerateKey();
        var ad = VaultCrypto.EnvelopeAssociatedData("device", userId);

        var envelope1 = VaultCrypto.WrapKey(device1Key, vaultKey, ad);
        var envelope2 = VaultCrypto.WrapKey(device2Key, vaultKey, ad);

        // "Revoke" device 1 by discarding its key — device 2 still works
        var unwrapped2 = VaultCrypto.UnwrapKey(device2Key, envelope2, ad);
        CollectionAssert.AreEqual(vaultKey, unwrapped2);

        // Device 1's envelope is still valid ciphertext, but only with device 1's key
        var unwrapped1 = VaultCrypto.UnwrapKey(device1Key, envelope1, ad);
        CollectionAssert.AreEqual(vaultKey, unwrapped1);
    }

    [TestMethod]
    public void New_Device_Approval_Creates_Valid_Envelope()
    {
        // Simulate: device 1 is approved, device 2 is pending, device 1 approves device 2
        var vaultKey = VaultCrypto.GenerateKey();
        var userId = Guid.NewGuid();
        var device1Key = VaultCrypto.GenerateKey();
        var device2Key = VaultCrypto.GenerateKey();
        var ad = VaultCrypto.EnvelopeAssociatedData("device", userId);

        // Device 1 has its envelope
        var envelope1 = VaultCrypto.WrapKey(device1Key, vaultKey, ad);

        // Device 1 unwraps VaultKey to create an envelope for device 2
        var unwrappedVaultKey = VaultCrypto.UnwrapKey(device1Key, envelope1, ad);
        var envelope2 = VaultCrypto.WrapKey(device2Key, unwrappedVaultKey, ad);

        // Device 2 can now unwrap
        var device2VaultKey = VaultCrypto.UnwrapKey(device2Key, envelope2, ad);
        CollectionAssert.AreEqual(vaultKey, device2VaultKey);
    }

    [TestMethod]
    public void Password_Verifier_Challenge_Response_Works()
    {
        var password = "user-password"u8.ToArray();
        var salt = Argon2Kdf.GenerateSalt();
        var authKey = Argon2Kdf.DeriveKey(password, salt, KdfConfig.Default);
        var verifier = HkdfHelper.DeriveVerifier(authKey);

        var nonce = PasswordVerifier.GenerateNonce();
        var sessionId = Guid.NewGuid();

        // Client computes proof
        var clientProof = PasswordVerifier.ComputeProof(verifier, nonce, sessionId);

        // Server verifies
        Assert.IsTrue(PasswordVerifier.VerifyClientProof(verifier, nonce, sessionId, clientProof));
    }

    [TestMethod]
    public void Password_Verifier_Rejects_Wrong_Proof()
    {
        var password = "user-password"u8.ToArray();
        var salt = Argon2Kdf.GenerateSalt();
        var authKey = Argon2Kdf.DeriveKey(password, salt, KdfConfig.Default);
        var verifier = HkdfHelper.DeriveVerifier(authKey);

        var nonce = PasswordVerifier.GenerateNonce();
        var sessionId = Guid.NewGuid();

        // Wrong proof (from different password)
        var wrongAuthKey = Argon2Kdf.DeriveKey("wrong-password"u8.ToArray(), salt, KdfConfig.Default);
        var wrongVerifier = HkdfHelper.DeriveVerifier(wrongAuthKey);
        var wrongProof = PasswordVerifier.ComputeProof(wrongVerifier, nonce, sessionId);

        Assert.IsFalse(PasswordVerifier.VerifyClientProof(verifier, nonce, sessionId, wrongProof));
    }

    [TestMethod]
    public void Password_Verifier_Rejects_Replayed_Nonce_With_Different_Session()
    {
        var password = "user-password"u8.ToArray();
        var salt = Argon2Kdf.GenerateSalt();
        var authKey = Argon2Kdf.DeriveKey(password, salt, KdfConfig.Default);
        var verifier = HkdfHelper.DeriveVerifier(authKey);

        var nonce = PasswordVerifier.GenerateNonce();
        var session1 = Guid.NewGuid();
        var session2 = Guid.NewGuid();

        var proof = PasswordVerifier.ComputeProof(verifier, nonce, session1);

        // Same nonce but different session ID should fail
        Assert.IsFalse(PasswordVerifier.VerifyClientProof(verifier, nonce, session2, proof));
    }

    [TestMethod]
    public void Recovery_Code_Hash_And_Verify_Works()
    {
        var code = "RC-4F8K-9Q2M";
        var salt = Argon2Kdf.GenerateSalt();

        var hash = Argon2Kdf.HashRecoveryCode(code, salt);

        Assert.IsTrue(Argon2Kdf.VerifyRecoveryCode(code, salt, hash));
    }

    [TestMethod]
    public void Recovery_Code_Verify_Rejects_Wrong_Code()
    {
        var code = "RC-4F8K-9Q2M";
        var wrongCode = "RC-XXXX-YYYY";
        var salt = Argon2Kdf.GenerateSalt();

        var hash = Argon2Kdf.HashRecoveryCode(code, salt);

        Assert.IsFalse(Argon2Kdf.VerifyRecoveryCode(wrongCode, salt, hash));
    }
}
