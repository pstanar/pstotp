import CryptoKit
import Foundation

/// ECDH P-256 device-envelope key exchange: each device unwraps the vault key with its own private key.
/// Wire format (matches web `packEcdhDeviceEnvelope` and Android `Ecdh`):
/// `base64(ephemeralPublicKey(65) || ciphertext+tag)` with the nonce sent separately.
public enum Ecdh {
    public typealias PrivateKey = P256.KeyAgreement.PrivateKey
    public typealias PublicKey = P256.KeyAgreement.PublicKey

    static let deviceEnvelopeContext = "device-envelope-v1"
    public static let publicKeyLength = 65  // 0x04 || X(32) || Y(32)

    public static func generateKeyPair() -> PrivateKey { PrivateKey() }

    /// 65-byte uncompressed point, interoperable with Web Crypto's raw export.
    public static func exportPublicKey(_ key: PublicKey) -> Data { key.x963Representation }

    public static func importPublicKey(_ bytes: Data) throws -> PublicKey {
        guard bytes.count == publicKeyLength, bytes.first == 0x04,
              let key = try? PublicKey(x963Representation: bytes) else { throw CryptoError.invalidPublicKey }
        return key
    }

    /// PKCS#8 DER, as Android stores it (device-local, never sent to the server).
    public static func exportPrivateKey(_ key: PrivateKey) -> Data { key.derRepresentation }

    public static func importPrivateKey(_ der: Data) throws -> PrivateKey {
        guard let key = try? PrivateKey(derRepresentation: der) else { throw CryptoError.invalidPrivateKey }
        return key
    }

    /// ECDH raw shared secret → HKDF-SHA256(info "device-envelope-v1") → 32 bytes.
    public static func deriveWrappingKey(privateKey: PrivateKey, publicKey: PublicKey) throws -> Data {
        let secret = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
        return Hkdf.derive(ikm: secret.withUnsafeBytes { Data($0) }, info: deviceEnvelopeContext)
    }

    /// Encrypts the vault key for `recipientPublicKey` using a fresh ephemeral key.
    public static func packDeviceEnvelope(vaultKey: Data, recipientPublicKey: PublicKey) throws -> Envelope {
        let ephemeral = generateKeyPair()
        let wrappingKey = try deriveWrappingKey(privateKey: ephemeral, publicKey: recipientPublicKey)
        let raw = try AesGcm.encrypt(key: wrappingKey, plaintext: vaultKey)
        let nonce = raw.prefix(AesGcm.nonceSize)
        let wire = exportPublicKey(ephemeral.publicKey) + raw.dropFirst(AesGcm.nonceSize)
        return Envelope(ciphertext: wire.base64EncodedString(), nonce: nonce.base64EncodedString())
    }

    public static func unpackDeviceEnvelope(_ envelope: Envelope, devicePrivateKey: PrivateKey) throws -> Data {
        guard let wire = Data(base64Encoded: envelope.ciphertext),
              let nonce = Data(base64Encoded: envelope.nonce) else { throw CryptoError.invalidEncoding }
        guard wire.count > publicKeyLength else { throw CryptoError.payloadTooShort }
        let ephemeral = try importPublicKey(wire.prefix(publicKeyLength))
        let wrappingKey = try deriveWrappingKey(privateKey: devicePrivateKey, publicKey: ephemeral)
        return try AesGcm.decrypt(key: wrappingKey, payload: nonce + wire.dropFirst(publicKeyLength))
    }
}
