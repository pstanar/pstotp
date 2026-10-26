import CryptoKit
import Foundation

/// AES-256-GCM encryption/decryption.
///
/// Payload format: [nonce (12 bytes)] [ciphertext + auth tag (16 bytes)]
/// Must match the web and Android clients for interop.
public enum AesGcm {
    static let nonceSize = 12
    static let keySize = 32

    /// - Returns: nonce || ciphertext || tag
    public static func encrypt(key: Data, plaintext: Data, associatedData: Data? = nil) throws -> Data {
        guard key.count == keySize else { throw CryptoError.invalidKeyLength(expected: keySize) }
        // No associated data and empty associated data are the same to GCM.
        let sealed = try AES.GCM.seal(
            plaintext, using: SymmetricKey(data: key), authenticating: associatedData ?? Data())
        // `combined` is nil only for non-12-byte nonces; CryptoKit generates 12.
        return sealed.combined!
    }

    /// - Parameter payload: nonce || ciphertext || tag
    public static func decrypt(key: Data, payload: Data, associatedData: Data? = nil) throws -> Data {
        guard key.count == keySize else { throw CryptoError.invalidKeyLength(expected: keySize) }
        guard payload.count > nonceSize else { throw CryptoError.payloadTooShort }
        do {
            let box = try AES.GCM.SealedBox(combined: payload)
            return try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: associatedData ?? Data())
        } catch {
            throw CryptoError.decryptionFailed
        }
    }
}
