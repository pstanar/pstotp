using PsTotp.Server.Application.DTOs;

namespace PsTotp.Server.Api.EndPoints;

public static class EnvelopeHelper
{
    public static byte[] ToBytes(EnvelopeDto envelope)
    {
        var ciphertext = Convert.FromBase64String(envelope.Ciphertext);
        var nonce = Convert.FromBase64String(envelope.Nonce);
        var result = new byte[nonce.Length + ciphertext.Length];
        nonce.CopyTo(result, 0);
        ciphertext.CopyTo(result, nonce.Length);
        return result;
    }

    public static EnvelopeDto FromBytes(byte[] payload)
    {
        const int nonceLen = 12;
        var nonce = Convert.ToBase64String(payload.AsSpan(0, nonceLen));
        var ciphertext = Convert.ToBase64String(payload.AsSpan(nonceLen));
        return new EnvelopeDto(ciphertext, nonce, 1);
    }
}
