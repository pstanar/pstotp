import Foundation

public enum OtpauthError: Error, Equatable, CustomStringConvertible {
    case notOtpauth
    case unsupportedType
    case missingSecret
    case unsupportedAlgorithm(String)
    case digitsOutOfRange
    case invalidPeriod

    public var description: String {
        switch self {
        case .notOtpauth: "Not an otpauth URI"
        case .unsupportedType: "Only TOTP is supported (not HOTP)"
        case .missingSecret: "Missing secret parameter"
        case .unsupportedAlgorithm(let a): "Unsupported algorithm: \(a)"
        case .digitsOutOfRange: "Digits must be between 4 and 10"
        case .invalidPeriod: "Period must be positive"
        }
    }
}

/// Parse and build otpauth:// URIs.
/// Format: otpauth://totp/[Issuer:]Account?secret=X&issuer=X&algorithm=SHA1&digits=6&period=30
public enum OtpauthUri {

    public static func parse(_ uriString: String) throws -> VaultEntryPlaintext {
        guard let components = URLComponents(string: uriString), components.scheme == "otpauth" else {
            throw OtpauthError.notOtpauth
        }
        guard components.host == "totp" else { throw OtpauthError.unsupportedType }

        var path = components.path   // percent-decoded, so "Issuer%3AAccount" is split below too
        if path.hasPrefix("/") { path.removeFirst() }

        let query = QueryParameters(components.percentEncodedQuery)
        guard let secret = query["secret"] else { throw OtpauthError.missingSecret }

        // Label: "Issuer:Account" or just "Account"
        let pathIssuer: String?
        let accountName: String
        if let colon = path.firstIndex(of: ":") {
            pathIssuer = String(path[..<colon])
            accountName = String(path[path.index(after: colon)...])
        } else {
            pathIssuer = nil
            accountName = path
        }

        // Query-parameter issuer takes precedence over the label's issuer.
        let issuer = query["issuer"] ?? pathIssuer ?? ""

        let algorithm = query["algorithm"]?.uppercased() ?? "SHA1"
        guard ["SHA1", "SHA256", "SHA512"].contains(algorithm) else {
            throw OtpauthError.unsupportedAlgorithm(algorithm)
        }

        let digits = query["digits"].flatMap { Int($0) } ?? 6
        guard (4...10).contains(digits) else { throw OtpauthError.digitsOutOfRange }

        let period = query["period"].flatMap { Int($0) } ?? 30
        guard period > 0 else { throw OtpauthError.invalidPeriod }

        return VaultEntryPlaintext(
            issuer: issuer,
            accountName: accountName,
            secret: secret.uppercased().replacingOccurrences(of: " ", with: ""),
            algorithm: algorithm,
            digits: digits,
            period: period
        )
    }

    public static func build(_ entry: VaultEntryPlaintext) -> String {
        var params = ["secret=\(encode(entry.secret))"]
        if !entry.issuer.isEmpty { params.append("issuer=\(encode(entry.issuer))") }
        params.append("algorithm=\(entry.algorithm)")
        params.append("digits=\(entry.digits)")
        params.append("period=\(entry.period)")
        return "otpauth://totp/\(encode(entry.accountName))?\(params.joined(separator: "&"))"
    }

    /// Percent-encode everything except RFC 3986 unreserved characters plus `!'()*`
    /// (same set as Android's `Uri.encode`).
    private static let allowed: CharacterSet = {
        var set = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        set.insert(charactersIn: "_-!.~'()*")
        return set
    }()

    private static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

/// Decoded query-string lookup: first occurrence wins, `+` means space, as on Android.
struct QueryParameters {
    private let pairs: [(String, String)]

    init(_ rawQuery: String?) {
        guard let rawQuery, !rawQuery.isEmpty else { pairs = []; return }
        pairs = rawQuery.split(separator: "&", omittingEmptySubsequences: true).map { part in
            let kv = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = Self.decode(String(kv[0]))
            let value = kv.count > 1 ? Self.decode(String(kv[1])) : ""
            return (key, value)
        }
    }

    subscript(key: String) -> String? {
        pairs.first { $0.0 == key }?.1
    }

    private static func decode(_ s: String) -> String {
        let spaced = s.replacingOccurrences(of: "+", with: " ")
        return spaced.removingPercentEncoding ?? spaced
    }
}
