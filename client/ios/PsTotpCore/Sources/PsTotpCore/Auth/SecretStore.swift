import Foundation

/// Where session secrets live: the Keychain on device (Android's `SecureStore`). They are kept out
/// of the database so a copy of the database file never contains tokens or the device key.
public protocol SecretStore: Sendable {
    func get(_ key: SecretKey) throws -> String?
    /// Writes all items; callers rely on both tokens being stored together.
    func setAll(_ items: [SecretKey: String]) throws
    func remove(_ key: SecretKey) throws
}

public enum SecretKey: String, Sendable, CaseIterable {
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
    /// Device ECDH private key (PKCS#8 DER, base64). Readable without the vault key, so a device
    /// envelope can be opened before the password is entered.
    case ecdhPrivateKey = "ecdh_private_key"
}

/// For tests and previews.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [SecretKey: String] = [:]

    public init() {}

    public func get(_ key: SecretKey) throws -> String? { lock.withLock { values[key] } }
    public func setAll(_ items: [SecretKey: String]) throws { lock.withLock { values.merge(items) { $1 } } }
    public func remove(_ key: SecretKey) throws { lock.withLock { _ = values.removeValue(forKey: key) } }
}
