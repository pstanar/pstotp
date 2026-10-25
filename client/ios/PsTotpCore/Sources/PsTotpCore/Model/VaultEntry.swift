import Foundation

/// Decrypted vault entry, held in memory.
/// Matches the web client's VaultEntry/VaultEntryPlaintext types.
public struct VaultEntry: Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var issuer: String
    public var accountName: String
    public var secret: String          // Base32-encoded
    public var algorithm: String
    public var digits: Int
    public var period: Int
    public var icon: String?           // Emoji or data URL
    public var version: Int
    public var sortOrder: Int

    public init(
        id: String,
        issuer: String,
        accountName: String,
        secret: String,
        algorithm: String = "SHA1",
        digits: Int = 6,
        period: Int = 30,
        icon: String? = nil,
        version: Int = 1,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.issuer = issuer
        self.accountName = accountName
        self.secret = secret
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
        self.icon = icon
        self.version = version
        self.sortOrder = sortOrder
    }
}

/// JSON-serializable plaintext for encryption. The encrypted payload stored locally is
/// this serialized as JSON → AES-GCM.
public struct VaultEntryPlaintext: Equatable, Hashable, Codable, Sendable {
    public var issuer: String
    public var accountName: String
    public var secret: String
    public var algorithm: String
    public var digits: Int
    public var period: Int
    public var icon: String?

    public init(
        issuer: String,
        accountName: String,
        secret: String,
        algorithm: String = "SHA1",
        digits: Int = 6,
        period: Int = 30,
        icon: String? = nil
    ) {
        self.issuer = issuer
        self.accountName = accountName
        self.secret = secret
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
        self.icon = icon
    }
}
