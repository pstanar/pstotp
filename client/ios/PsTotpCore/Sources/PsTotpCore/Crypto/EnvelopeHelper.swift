import Foundation

/// Converts between AES-GCM payloads (`nonce || ciphertext+tag`) and API `Envelope` DTOs
/// (`base64(ciphertext+tag)`, `base64(nonce)`, version 1).
public enum EnvelopeHelper {
    static let nonceSize = AesGcm.nonceSize

    public static func encrypt(key: Data, plaintext: Data) throws -> Envelope {
        fromRaw(try AesGcm.encrypt(key: key, plaintext: plaintext))
    }

    public static func decrypt(key: Data, envelope: Envelope) throws -> Data {
        try AesGcm.decrypt(key: key, payload: try toRaw(envelope))
    }

    public static func fromRaw(_ raw: Data) -> Envelope {
        Envelope(ciphertext: raw.dropFirst(nonceSize).base64EncodedString(),
                 nonce: raw.prefix(nonceSize).base64EncodedString())
    }

    public static func toRaw(_ envelope: Envelope) throws -> Data {
        guard let nonce = Data(base64Encoded: envelope.nonce),
              let ciphertext = Data(base64Encoded: envelope.ciphertext) else { throw CryptoError.invalidEncoding }
        return nonce + ciphertext
    }
}
