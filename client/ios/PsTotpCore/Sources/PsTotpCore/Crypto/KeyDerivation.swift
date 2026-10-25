import Foundation
import Security

/// Password-based key derivation flow.
///
/// password → Argon2id(salt) → authKey → HKDF → verifier / envelopeKey
/// Context strings MUST be identical to the web and Android clients for interop.
public enum KeyDerivation {
    private static let authVerifierContext = "auth-verifier-v1"
    private static let passwordEnvelopeContext = "vault-password-envelope-v1"
    private static let recoveryUnlockContext = "totp-vault-recovery-unlock-v1"
    public static let deviceEcdhKeyContext = "device-ecdh-private-key-v1"

    public struct SetupResult {
        public let salt: Data
        public let verifier: Data
        public let encryptedVaultKey: Data
        public let vaultKey: Data
    }

    public static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return Data(bytes)
    }

    /// Random 16-byte salt for Argon2id.
    public static func generateSalt() -> Data { randomBytes(16) }

    /// Random 32-byte vault key.
    public static func generateVaultKey() -> Data { randomBytes(32) }

    public static func derivePasswordAuthKey(password: String, salt: Data) throws -> Data {
        try Argon2.hash(password: password, salt: salt)
    }

    public static func deriveVerifier(authKey: Data) -> Data {
        Hkdf.derive(ikm: authKey, info: authVerifierContext)
    }

    public static func deriveEnvelopeKey(authKey: Data) -> Data {
        Hkdf.derive(ikm: authKey, info: passwordEnvelopeContext)
    }

    public static func deriveRecoveryUnlockKey(recoverySeed: Data) -> Data {
        Hkdf.derive(ikm: recoverySeed, info: recoveryUnlockContext)
    }

    public static func setupPassword(_ password: String) throws -> SetupResult {
        let salt = generateSalt()
        let vaultKey = generateVaultKey()
        let authKey = try derivePasswordAuthKey(password: password, salt: salt)
        let verifier = deriveVerifier(authKey: authKey)
        let envelopeKey = deriveEnvelopeKey(authKey: authKey)
        let encryptedVaultKey = try AesGcm.encrypt(key: envelopeKey, plaintext: vaultKey)
        return SetupResult(salt: salt, verifier: verifier, encryptedVaultKey: encryptedVaultKey, vaultKey: vaultKey)
    }

    /// - Returns: The vault key, or nil if the password is wrong.
    public static func unlockVault(password: String, salt: Data, storedVerifier: Data, encryptedVaultKey: Data) throws -> Data? {
        let authKey = try derivePasswordAuthKey(password: password, salt: salt)
        let verifier = deriveVerifier(authKey: authKey)
        guard constantTimeEquals(verifier, storedVerifier) else { return nil }
        let envelopeKey = deriveEnvelopeKey(authKey: authKey)
        return try? AesGcm.decrypt(key: envelopeKey, payload: encryptedVaultKey)
    }
}
