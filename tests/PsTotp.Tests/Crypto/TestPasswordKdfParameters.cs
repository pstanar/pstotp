using PsTotp.Server.Application.Crypto;

namespace PsTotp.Tests.Crypto;

[TestClass]
public class TestPasswordKdfParameters
{
    [TestMethod]
    public void Default_Config_Uses_Argon2id()
    {
        var config = KdfConfig.Default;
        Assert.AreEqual("argon2id", config.Algorithm);
    }

    [TestMethod]
    public void Default_Config_Uses_Pinned_Parameters()
    {
        var config = KdfConfig.Default;
        Assert.AreEqual(64, config.MemoryMb);
        Assert.AreEqual(3, config.Iterations);
        Assert.AreEqual(4, config.Parallelism);
        Assert.AreEqual(32, config.HashLength);
    }

    [TestMethod]
    public void DeriveKey_Produces_Correct_Length()
    {
        var password = "test-password"u8.ToArray();
        var salt = Argon2Kdf.GenerateSalt();
        var config = KdfConfig.Default;

        var key = Argon2Kdf.DeriveKey(password, salt, config);

        Assert.HasCount(config.HashLength, key);
    }

    [TestMethod]
    public void DeriveKey_Is_Deterministic_For_Same_Inputs()
    {
        var password = "test-password"u8.ToArray();
        var salt = Argon2Kdf.GenerateSalt();
        var config = KdfConfig.Default;

        var key1 = Argon2Kdf.DeriveKey(password, salt, config);
        var key2 = Argon2Kdf.DeriveKey(password, salt, config);

        CollectionAssert.AreEqual(key1, key2);
    }

    [TestMethod]
    public void DeriveKey_Differs_For_Different_Passwords()
    {
        var salt = Argon2Kdf.GenerateSalt();
        var config = KdfConfig.Default;

        var key1 = Argon2Kdf.DeriveKey("password-a"u8.ToArray(), salt, config);
        var key2 = Argon2Kdf.DeriveKey("password-b"u8.ToArray(), salt, config);

        CollectionAssert.AreNotEqual(key1, key2);
    }

    [TestMethod]
    public void DeriveKey_Differs_For_Different_Salts()
    {
        var password = "test-password"u8.ToArray();
        var config = KdfConfig.Default;

        var key1 = Argon2Kdf.DeriveKey(password, Argon2Kdf.GenerateSalt(), config);
        var key2 = Argon2Kdf.DeriveKey(password, Argon2Kdf.GenerateSalt(), config);

        CollectionAssert.AreNotEqual(key1, key2);
    }

    [TestMethod]
    public void GenerateSalt_Produces_Correct_Length()
    {
        var salt = Argon2Kdf.GenerateSalt();
        Assert.HasCount(16, salt);
    }

    [TestMethod]
    public void GenerateSalt_Produces_Unique_Values()
    {
        var salt1 = Argon2Kdf.GenerateSalt();
        var salt2 = Argon2Kdf.GenerateSalt();

        CollectionAssert.AreNotEqual(salt1, salt2);
    }

    [TestMethod]
    public void DeriveKey_Rejects_Unsupported_Algorithm()
    {
        var password = "test"u8.ToArray();
        var salt = Argon2Kdf.GenerateSalt();
        var config = KdfConfig.Default with { Algorithm = "bcrypt" };

        Assert.ThrowsExactly<ArgumentException>(() => Argon2Kdf.DeriveKey(password, salt, config));
    }

    [TestMethod]
    public void Hkdf_Verifier_And_EnvelopeKey_Differ()
    {
        var password = "test-password"u8.ToArray();
        var salt = Argon2Kdf.GenerateSalt();
        var authKey = Argon2Kdf.DeriveKey(password, salt, KdfConfig.Default);

        var verifier = HkdfHelper.DeriveVerifier(authKey);
        var envelopeKey = HkdfHelper.DerivePasswordEnvelopeKey(authKey);

        CollectionAssert.AreNotEqual(verifier, envelopeKey,
            "Verifier and envelope key must use different HKDF contexts to prevent cross-derivation");
    }
}
