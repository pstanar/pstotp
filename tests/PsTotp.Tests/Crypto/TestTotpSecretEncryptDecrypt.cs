using PsTotp.Server.Application.Crypto;

namespace PsTotp.Tests.Crypto;

[TestClass]
public class TestTotpSecretEncryptDecrypt
{
    [TestMethod]
    public void EncryptDecrypt_RoundTrips_VaultEntry()
    {
        var vaultKey = VaultCrypto.GenerateKey();
        var entryId = Guid.NewGuid();
        var entry = new VaultEntryPlaintext
        {
            Issuer = "GitHub",
            AccountName = "alice@example.com",
            Secret = "JBSWY3DPEHPK3PXP",
        };

        var encrypted = VaultCrypto.EncryptEntry(vaultKey, entry, entryId);
        var decrypted = VaultCrypto.DecryptEntry(vaultKey, encrypted, entryId);

        Assert.AreEqual(entry.Issuer, decrypted.Issuer);
        Assert.AreEqual(entry.AccountName, decrypted.AccountName);
        Assert.AreEqual(entry.Secret, decrypted.Secret);
        Assert.AreEqual(entry.Algorithm, decrypted.Algorithm);
        Assert.AreEqual(entry.Digits, decrypted.Digits);
        Assert.AreEqual(entry.Period, decrypted.Period);
    }

    [TestMethod]
    public void EncryptDecrypt_Preserves_NonDefault_Parameters()
    {
        var vaultKey = VaultCrypto.GenerateKey();
        var entryId = Guid.NewGuid();
        var entry = new VaultEntryPlaintext
        {
            Issuer = "AWS",
            AccountName = "admin",
            Secret = "HXDMVJECJJWSRB3HWIZR4IFUGFTMXBOZ",
            Algorithm = "SHA256",
            Digits = 8,
            Period = 60,
        };

        var encrypted = VaultCrypto.EncryptEntry(vaultKey, entry, entryId);
        var decrypted = VaultCrypto.DecryptEntry(vaultKey, encrypted, entryId);

        Assert.AreEqual("SHA256", decrypted.Algorithm);
        Assert.AreEqual(8, decrypted.Digits);
        Assert.AreEqual(60, decrypted.Period);
    }

    [TestMethod]
    public void Decrypt_Fails_With_Wrong_VaultKey()
    {
        var vaultKey = VaultCrypto.GenerateKey();
        var wrongKey = VaultCrypto.GenerateKey();
        var entryId = Guid.NewGuid();
        var entry = new VaultEntryPlaintext
        {
            Issuer = "GitHub",
            AccountName = "alice@example.com",
            Secret = "JBSWY3DPEHPK3PXP",
        };

        var encrypted = VaultCrypto.EncryptEntry(vaultKey, entry, entryId);

        Assert.ThrowsExactly<System.Security.Cryptography.AuthenticationTagMismatchException>(
            () => VaultCrypto.DecryptEntry(wrongKey, encrypted, entryId));
    }

    [TestMethod]
    public void Decrypt_Fails_With_Wrong_EntryId()
    {
        var vaultKey = VaultCrypto.GenerateKey();
        var entryId = Guid.NewGuid();
        var wrongEntryId = Guid.NewGuid();
        var entry = new VaultEntryPlaintext
        {
            Issuer = "GitHub",
            AccountName = "alice@example.com",
            Secret = "JBSWY3DPEHPK3PXP",
        };

        var encrypted = VaultCrypto.EncryptEntry(vaultKey, entry, entryId);

        Assert.ThrowsExactly<System.Security.Cryptography.AuthenticationTagMismatchException>(
            () => VaultCrypto.DecryptEntry(vaultKey, encrypted, wrongEntryId));
    }

    [TestMethod]
    public void Decrypt_Fails_With_Tampered_Payload()
    {
        var vaultKey = VaultCrypto.GenerateKey();
        var entryId = Guid.NewGuid();
        var entry = new VaultEntryPlaintext
        {
            Issuer = "GitHub",
            AccountName = "alice@example.com",
            Secret = "JBSWY3DPEHPK3PXP",
        };

        var encrypted = VaultCrypto.EncryptEntry(vaultKey, entry, entryId);
        encrypted[encrypted.Length / 2] ^= 0xFF;

        Assert.ThrowsExactly<System.Security.Cryptography.AuthenticationTagMismatchException>(
            () => VaultCrypto.DecryptEntry(vaultKey, encrypted, entryId));
    }

    [TestMethod]
    public void Encrypt_Produces_Different_Ciphertext_Each_Time()
    {
        var vaultKey = VaultCrypto.GenerateKey();
        var entryId = Guid.NewGuid();
        var entry = new VaultEntryPlaintext
        {
            Issuer = "GitHub",
            AccountName = "alice@example.com",
            Secret = "JBSWY3DPEHPK3PXP",
        };

        var encrypted1 = VaultCrypto.EncryptEntry(vaultKey, entry, entryId);
        var encrypted2 = VaultCrypto.EncryptEntry(vaultKey, entry, entryId);

        CollectionAssert.AreNotEqual(encrypted1, encrypted2,
            "Each encryption must use a unique nonce");
    }

    [TestMethod]
    public void Encrypted_Payload_Contains_No_Plaintext_Secrets()
    {
        var vaultKey = VaultCrypto.GenerateKey();
        var entryId = Guid.NewGuid();
        var secret = "JBSWY3DPEHPK3PXP";
        var entry = new VaultEntryPlaintext
        {
            Issuer = "GitHub",
            AccountName = "alice@example.com",
            Secret = secret,
        };

        var encrypted = VaultCrypto.EncryptEntry(vaultKey, entry, entryId);
        var payloadString = System.Text.Encoding.UTF8.GetString(encrypted);

        Assert.DoesNotContain(payloadString, secret,
            "Encrypted payload must not contain the plaintext TOTP secret");
        Assert.DoesNotContain(payloadString, "GitHub",
            "Encrypted payload must not contain the plaintext issuer");
    }
}
