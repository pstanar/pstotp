using System.Security.Cryptography;
using System.Text;
using PsTotp.Server.Application.Crypto;

namespace PsTotp.Tests.Crypto;

/// <summary>
/// Tests that verify backend crypto matches expected frontend behavior.
/// These test vectors can be used to validate the frontend implementation.
/// </summary>
[TestClass]
public class TestCrossplatformCrypto
{
    [TestMethod]
    public void GuidToByteArray_Produces_MixedEndian()
    {
        // This is the exact layout the frontend must match in guidToBytes()
        var guid = new Guid("01020304-0506-0708-090a-0b0c0d0e0f10");
        var bytes = guid.ToByteArray();

        var expected = new byte[]
        {
            0x04, 0x03, 0x02, 0x01, // first 4 bytes LE
            0x06, 0x05,             // next 2 bytes LE
            0x08, 0x07,             // next 2 bytes LE
            0x09, 0x0a,             // next 2 bytes BE
            0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10, // last 6 bytes BE
        };

        CollectionAssert.AreEqual(expected, bytes);
    }

    [TestMethod]
    public void HkdfDerive_PasswordVerifier_Is_Deterministic()
    {
        var ikm = new byte[32];
        Array.Fill(ikm, (byte)0xAA);

        var result1 = HkdfHelper.DeriveVerifier(ikm);
        var result2 = HkdfHelper.DeriveVerifier(ikm);

        CollectionAssert.AreEqual(result1, result2);
        Assert.HasCount(32, result1);
    }

    [TestMethod]
    public void HkdfDerive_DifferentContexts_ProduceDifferentKeys()
    {
        var ikm = new byte[32];
        Array.Fill(ikm, (byte)0xBB);

        var verifier = HkdfHelper.DeriveVerifier(ikm);
        var envelopeKey = HkdfHelper.DerivePasswordEnvelopeKey(ikm);

        CollectionAssert.AreNotEqual(verifier, envelopeKey);
    }

    [TestMethod]
    public void HkdfDerive_EmptySalt_MatchesWebCrypto()
    {
        // Backend HkdfHelper.DeriveKey passes no salt to HKDF.DeriveKey.
        // The .NET HKDF implementation uses an empty salt by default.
        // Frontend must use salt: new Uint8Array(0) explicitly.
        var ikm = new byte[32];
        Array.Fill(ikm, (byte)0xCC);

        var info = Encoding.UTF8.GetBytes(HkdfHelper.AuthVerifierContext);
        var result = HKDF.DeriveKey(HashAlgorithmName.SHA256, ikm, 32, info: info);

        // Verify it matches the helper
        var helperResult = HkdfHelper.DeriveVerifier(ikm);
        CollectionAssert.AreEqual(helperResult, result);
    }

    [TestMethod]
    public void ClientProof_Computation_Is_Deterministic()
    {
        var verifier = new byte[32];
        Array.Fill(verifier, (byte)0x11);

        var nonce = new byte[32];
        Array.Fill(nonce, (byte)0x22);

        var sessionId = new Guid("aabbccdd-eeff-1122-3344-556677889900");

        var proof1 = PasswordVerifier.ComputeProof(verifier, nonce, sessionId);
        var proof2 = PasswordVerifier.ComputeProof(verifier, nonce, sessionId);

        CollectionAssert.AreEqual(proof1, proof2);
        Assert.HasCount(32, proof1); // HMAC-SHA256 output
    }

    [TestMethod]
    public void ClientProof_Uses_Nonce_Concat_SessionIdBytes()
    {
        // Verify the message format: nonce || sessionId.ToByteArray()
        var verifier = new byte[32];
        Array.Fill(verifier, (byte)0x42);

        var nonce = new byte[32];
        Array.Fill(nonce, (byte)0xAA);

        var sessionId = Guid.NewGuid();

        // Manually compute what the proof should be
        var message = new byte[nonce.Length + 16];
        nonce.CopyTo(message, 0);
        sessionId.ToByteArray().CopyTo(message, nonce.Length);

        using var hmac = new HMACSHA256(verifier);
        var expected = hmac.ComputeHash(message);

        var actual = PasswordVerifier.ComputeProof(verifier, nonce, sessionId);

        CollectionAssert.AreEqual(expected, actual);
    }

    [TestMethod]
    public void AesGcm_PackedPayload_Layout()
    {
        var key = VaultCrypto.GenerateKey();
        var plaintext = Encoding.UTF8.GetBytes("test data");

        var packed = AesGcmHelper.Encrypt(key, plaintext);

        // Layout: nonce (12) || ciphertext (9) || tag (16) = 37 bytes
        Assert.HasCount(12 + plaintext.Length + 16, packed);

        // Verify it decrypts
        var decrypted = AesGcmHelper.Decrypt(key, packed);
        CollectionAssert.AreEqual(plaintext, decrypted);
    }

    [TestMethod]
    public void VaultEntry_AssociatedData_Format()
    {
        var entryId = new Guid("550e8400-e29b-41d4-a716-446655440000");
        var ad = VaultCrypto.EnvelopeAssociatedData("password", entryId);

        // Should be UTF-8 of "{type}:{guid}"
        var expected = Encoding.UTF8.GetBytes("password:550e8400-e29b-41d4-a716-446655440000");
        CollectionAssert.AreEqual(expected, ad);
    }
}
