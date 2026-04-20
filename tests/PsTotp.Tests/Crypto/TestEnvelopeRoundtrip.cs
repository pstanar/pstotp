using PsTotp.Server.Application.Crypto;
using PsTotp.Server.Application.DTOs;
using PsTotp.Server.Api.EndPoints;

namespace PsTotp.Tests.Crypto;

[TestClass]
public class TestEnvelopeRoundtrip
{
    [TestMethod]
    public void EnvelopeToBytes_EnvelopeFromBytes_Roundtrips()
    {
        var key = VaultCrypto.GenerateKey();
        var vaultKey = VaultCrypto.GenerateKey();

        // Encrypt to get nonce + ciphertext
        var packed = AesGcmHelper.Encrypt(key, vaultKey);

        // Split into nonce and ciphertext for DTO
        var nonce = Convert.ToBase64String(packed.AsSpan(0, AesGcmHelper.NonceLength));
        var ciphertext = Convert.ToBase64String(packed.AsSpan(AesGcmHelper.NonceLength));

        var dto = new EnvelopeDto(ciphertext, nonce, 1);

        // Pack and unpack
        var bytes = EnvelopeHelper.ToBytes(dto);
        var restored = EnvelopeHelper.FromBytes(bytes);

        Assert.AreEqual(dto.Nonce, restored.Nonce);
        Assert.AreEqual(dto.Ciphertext, restored.Ciphertext);
        Assert.AreEqual(1, restored.Version);
    }

    [TestMethod]
    public void EnvelopeToBytes_Produces_Correct_Layout()
    {
        // nonce = 12 bytes, ciphertext = arbitrary
        var nonce = new byte[12];
        var ciphertext = new byte[48]; // 32 + 16 tag
        Random.Shared.NextBytes(nonce);
        Random.Shared.NextBytes(ciphertext);

        var dto = new EnvelopeDto(
            Convert.ToBase64String(ciphertext),
            Convert.ToBase64String(nonce),
            1);

        var packed = EnvelopeHelper.ToBytes(dto);

        // First 12 bytes should be nonce
        CollectionAssert.AreEqual(nonce, packed.AsSpan(0, 12).ToArray());
        // Rest should be ciphertext
        CollectionAssert.AreEqual(ciphertext, packed.AsSpan(12).ToArray());
    }

    [TestMethod]
    public void EnvelopeFromBytes_Splits_At_Byte_12()
    {
        var payload = new byte[60]; // 12 nonce + 48 ciphertext
        Random.Shared.NextBytes(payload);

        var dto = EnvelopeHelper.FromBytes(payload);

        var expectedNonce = Convert.ToBase64String(payload.AsSpan(0, 12));
        var expectedCiphertext = Convert.ToBase64String(payload.AsSpan(12));

        Assert.AreEqual(expectedNonce, dto.Nonce);
        Assert.AreEqual(expectedCiphertext, dto.Ciphertext);
    }
}
