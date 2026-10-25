import CryptoKit
import Foundation

/// HKDF-SHA256 key derivation (RFC 5869).
///
/// Context strings give domain separation:
/// - "auth-verifier-v1", "vault-password-envelope-v1",
///   "totp-vault-recovery-unlock-v1", "device-envelope-v1"
///
/// Must match the web and Android clients: NO salt, context string as info.
public enum Hkdf {
    public static func derive(ikm: Data, info: String, length: Int = 32) -> Data {
        // An empty salt and a zero-filled hash-length salt are the same HMAC key (RFC 5869 §2.2).
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ikm),
            salt: Data(),
            info: Data(info.utf8),
            outputByteCount: length
        )
        return key.withUnsafeBytes { Data($0) }
    }

    public static func hmacSha256(key: Data, data: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
    }
}
