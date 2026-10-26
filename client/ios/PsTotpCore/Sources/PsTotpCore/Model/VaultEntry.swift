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

    public init(id: String, plaintext p: VaultEntryPlaintext, version: Int = 1, sortOrder: Int = 0) {
        self.init(
            id: id, issuer: p.issuer, accountName: p.accountName, secret: p.secret,
            algorithm: p.algorithm, digits: p.digits, period: p.period, icon: p.icon,
            version: version, sortOrder: sortOrder)
    }

    /// The TOTP code at `timestampSeconds`, or nil when the entry can't produce one (bad secret or
    /// parameters).
    public func code(at timestampSeconds: Int64) -> String? {
        try? TotpGenerator.generate(
            secret: secret, algorithm: algorithm, digits: digits, period: period,
            timestampSeconds: timestampSeconds)
    }

    /// The encryptable / exportable part of the entry.
    public var plaintext: VaultEntryPlaintext {
        VaultEntryPlaintext(
            issuer: issuer, accountName: accountName, secret: secret,
            algorithm: algorithm, digits: digits, period: period, icon: icon)
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

// MARK: - JSON shape

/// One JSON shape for the encrypted vault payload and the plain/encrypted export formats.
extension VaultEntryPlaintext {
    var jsonObject: JSONObject {
        var obj: JSONObject = [
            "issuer": issuer, "accountName": accountName, "secret": secret,
            "algorithm": algorithm, "digits": digits, "period": period,
        ]
        if let icon { obj["icon"] = icon }
        return obj
    }

    /// Lenient like Android's org.json reads: optional fields default, an empty icon means none.
    /// - Returns: nil when `issuer`, `accountName` or `secret` is missing.
    init?(json obj: JSONObject) {
        guard let issuer = obj["issuer"] as? String,
              let accountName = obj["accountName"] as? String,
              let secret = obj["secret"] as? String
        else { return nil }
        self.init(
            issuer: issuer, accountName: accountName, secret: secret,
            algorithm: obj.optString("algorithm", "SHA1"),
            digits: obj.optInt("digits", 6),
            period: obj.optInt("period", 30),
            icon: obj.optStringField("icon"))
    }
}
