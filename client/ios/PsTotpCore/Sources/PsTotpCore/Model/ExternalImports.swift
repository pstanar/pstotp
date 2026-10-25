import Foundation

public enum ImportParseError: Error, Equatable, CustomStringConvertible {
    case truncatedVarint
    case varintTooLong
    case badLengthDelimited
    case unsupportedWireType(Int)
    case truncatedFixedWidth
    case invalidBase64

    public var description: String {
        switch self {
        case .truncatedVarint: "truncated varint"
        case .varintTooLong: "varint too long"
        case .badLengthDelimited: "bad length-delimited"
        case .unsupportedWireType(let w): "unsupported wire type \(w)"
        case .truncatedFixedWidth: "truncated fixed-width field"
        case .invalidBase64: "invalid base64 payload"
        }
    }
}

/// Parsers for third-party TOTP export formats:
///   - Google Authenticator (otpauth-migration:// URIs, protobuf payload)
///   - Aegis (plain / unencrypted JSON only)
///   - 2FAS (plain JSON export)
///
/// Each `tryParseX` returns nil when the content doesn't look like that format, so
/// auto-detect can probe them in turn without throwing.
enum ExternalImports {

    /// Build a data URL from an embedded import icon. Aegis stores raw base64 plus `icon_mime`;
    /// 2FAS custom images arrive as a base64 string. Anything else (e.g. 2FAS brand-id objects)
    /// yields nil.
    private static func embeddedIconDataUrl(_ icon: String?, mime: String?) -> String? {
        guard let icon, !icon.isEmpty else { return nil }
        if icon.hasPrefix("data:") { return icon }
        let mimeType = (mime?.isEmpty == false) ? mime! : "image/png"
        return "data:\(mimeType);base64,\(icon)"
    }

    // MARK: Google Authenticator

    /// Parses an otpauth-migration:// URI (the "Transfer accounts" QR code).
    static func tryParseGoogleAuthMigration(_ content: String) throws -> [VaultEntryPlaintext]? {
        let line = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("otpauth-migration://") else { return nil }

        guard let rawQuery = URLComponents(string: line)?.percentEncodedQuery,
              let dataParam = rawQuery.split(separator: "&").first(where: { $0.hasPrefix("data=") })
        else { return nil }

        // Standard base64, usually with the padding / '+' percent-encoded. Unlike Java's
        // URLDecoder we keep a literal '+' as '+' — it is a base64 digit here, not a space.
        let value = String(dataParam.dropFirst("data=".count))
        let b64 = value.removingPercentEncoding ?? value
        guard let payload = Data(base64Encoded: b64) else { throw ImportParseError.invalidBase64 }
        return try parseMigrationPayload(payload)
    }

    private static func parseMigrationPayload(_ bytes: Data) throws -> [VaultEntryPlaintext] {
        var reader = ProtoReader(bytes)
        var out = [VaultEntryPlaintext]()
        while !reader.eof {
            let (field, wire) = try reader.readTag()
            if field == 1 && wire == ProtoReader.lengthDelimited {
                let inner = try reader.readLengthDelimited()
                if let entry = try parseOtpParameters(inner) { out.append(entry) }
            } else {
                try reader.skipField(wire)
            }
        }
        return out
    }

    private static func parseOtpParameters(_ bytes: Data) throws -> VaultEntryPlaintext? {
        var reader = ProtoReader(bytes)
        var secret = Data()
        var name = ""
        var issuer = ""
        var algo = 1
        var digits = 1
        var type = 2
        while !reader.eof {
            let (field, wire) = try reader.readTag()
            switch field {
            case 1: secret = try reader.readLengthDelimited()
            case 2: name = String(decoding: try reader.readLengthDelimited(), as: UTF8.self)
            case 3: issuer = String(decoding: try reader.readLengthDelimited(), as: UTF8.self)
            case 4: algo = Int(truncatingIfNeeded: try reader.readVarint())
            case 5: digits = Int(truncatingIfNeeded: try reader.readVarint())
            case 6: type = Int(truncatingIfNeeded: try reader.readVarint())
            default: try reader.skipField(wire)
            }
        }
        if type != 2 { return nil } // HOTP — TOTP only

        let algorithmName: String
        switch algo {
        case 2: algorithmName = "SHA256"
        case 3: algorithmName = "SHA512"
        default: algorithmName = "SHA1"
        }
        let digitCount = digits == 2 ? 8 : 6
        let (resolvedIssuer, resolvedAccount) = resolveIssuerAndAccount(issuer: issuer, name: name)
        let issuerOrUnknown = resolvedIssuer.isBlank ? "Unknown" : resolvedIssuer
        let account = resolvedAccount.isBlank
            ? (resolvedIssuer.isBlank ? "Account" : resolvedIssuer)
            : resolvedAccount
        return VaultEntryPlaintext(
            issuer: issuerOrUnknown,
            accountName: account,
            secret: Base32.encode(secret),
            algorithm: algorithmName,
            digits: digitCount,
            period: 30,
            icon: nil
        )
    }

    /// Google Authenticator is inconsistent about what it puts in `name` when `issuer` is set:
    ///   - no colon in name                 → use name as-is
    ///   - issuer blank + colon in name     → split "Issuer:account"
    ///   - issuer matches prefix before ':' → strip the redundant prefix
    ///   - otherwise                        → the colon belongs to the account; leave name alone
    private static func resolveIssuerAndAccount(issuer: String, name: String) -> (String, String) {
        guard let colon = name.firstIndex(of: ":") else { return (issuer, name) }
        let before = name[..<colon].trimmed
        let after = name[name.index(after: colon)...].trimmed
        if issuer.isBlank { return (before, after) }
        if before.caseInsensitiveCompare(issuer) == .orderedSame { return (issuer, after) }
        return (issuer, name)
    }

    // MARK: Aegis

    /// Plain (unencrypted) Aegis export: `{ "version":1, "header":{…}, "db":{"entries":[…]} }`.
    static func tryParseAegis(_ json: JSONObject) -> [VaultEntryPlaintext]? {
        guard let db = json.optObject("db"), let entries = db.optArray("entries") else { return nil }
        // Only claim the format if the top-level "header" is present too.
        guard json.has("header") else { return nil }

        var out = [VaultEntryPlaintext]()
        for case let e as JSONObject in entries {
            guard e.optString("type") == "totp", let info = e.optObject("info") else { continue }
            let secret = info.optString("secret")
            guard !secret.isBlank else { continue }
            let issuer = e.optString("issuer")
            let name = e.optString("name")
            out.append(VaultEntryPlaintext(
                issuer: issuer.isBlank ? "Unknown" : issuer,
                accountName: name.isBlank ? "Account" : name,
                secret: secret.uppercased(),
                algorithm: info.optString("algo", "SHA1").uppercased(),
                digits: info.optInt("digits", 6),
                period: info.optInt("period", 30),
                icon: embeddedIconDataUrl(e.optStringField("icon"), mime: e.optStringField("icon_mime"))
            ))
        }
        return out.isEmpty ? nil : out
    }

    // MARK: 2FAS

    static func tryParse2Fas(_ json: JSONObject) -> [VaultEntryPlaintext]? {
        guard let services = json.optArray("services") else { return nil }
        // `schemaVersion` is the 2FAS-specific anchor.
        guard json.has("schemaVersion") else { return nil }

        var out = [VaultEntryPlaintext]()
        for case let svc as JSONObject in services {
            let secret = svc.optString("secret")
            guard !secret.isBlank else { continue }
            let otp = svc.optObject("otp") ?? [:]
            let name = svc.optString("name")
            var issuer = otp.optString("issuer")
            if issuer.isBlank { issuer = name }
            if issuer.isBlank { issuer = "Unknown" }
            var account = otp.optString("account")
            if account.isBlank { account = name }
            if account.isBlank { account = issuer }
            out.append(VaultEntryPlaintext(
                issuer: issuer,
                accountName: account,
                secret: secret.uppercased(),
                algorithm: otp.optString("algorithm", "SHA1").uppercased(),
                digits: otp.optInt("digits", 6),
                period: otp.optInt("period", 30),
                // 2FAS icons are usually brand-id objects we can't resolve; only a rare
                // embedded custom image string yields a data URL.
                icon: embeddedIconDataUrl(svc.optStringField("icon"), mime: nil)
            ))
        }
        return out.isEmpty ? nil : out
    }
}

// MARK: - Minimal protobuf reader

private struct ProtoReader {
    static let varint = 0
    static let lengthDelimited = 2

    private let buf: [UInt8]
    private var pos = 0

    init(_ data: Data) { buf = [UInt8](data) }

    var eof: Bool { pos >= buf.count }

    mutating func readTag() throws -> (field: Int, wire: Int) {
        let tag = UInt32(truncatingIfNeeded: try readVarint())
        return (Int(tag >> 3), Int(tag & 0x7))
    }

    mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            guard pos < buf.count else { throw ImportParseError.truncatedVarint }
            let b = buf[pos]
            pos += 1
            result |= UInt64(b & 0x7F) << shift
            if b & 0x80 == 0 { return result }
            shift += 7
            if shift > 63 { throw ImportParseError.varintTooLong }
        }
    }

    mutating func readLengthDelimited() throws -> Data {
        let len = Int(Int32(truncatingIfNeeded: try readVarint()))
        guard len >= 0, pos + len <= buf.count else { throw ImportParseError.badLengthDelimited }
        defer { pos += len }
        return Data(buf[pos..<(pos + len)])
    }

    mutating func skipField(_ wire: Int) throws {
        switch wire {
        case Self.varint: _ = try readVarint()
        case 1: try skip(8)                       // fixed64
        case Self.lengthDelimited: _ = try readLengthDelimited()
        case 5: try skip(4)                       // fixed32
        default: throw ImportParseError.unsupportedWireType(wire)
        }
    }

    private mutating func skip(_ n: Int) throws {
        guard pos + n <= buf.count else { throw ImportParseError.truncatedFixedWidth }
        pos += n
    }
}

private extension StringProtocol {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var isBlank: Bool { trimmed.isEmpty }
}
