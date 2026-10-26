import Foundation

public enum EntryValidationError: Error, Equatable, CustomStringConvertible {
    case secretRequired
    case secretInvalid
    case digitsOutOfRange
    case periodInvalid
    case algorithmUnsupported

    public var description: String {
        switch self {
        case .secretRequired: "Secret key is required"
        case .secretInvalid: "Secret key is not valid Base32"
        case .digitsOutOfRange: "Digits must be between 4 and 10"
        case .periodInvalid: "Period must be a positive number"
        case .algorithmUnsupported: "Unsupported algorithm"
        }
    }
}

/// Validation for new entries, whether typed in, scanned, or imported from a file.
///
/// Android's manual form accepts any secret and the card then fails when it generates a code;
/// iOS rejects a secret that isn't decodable Base32 up front.
public enum EntryValidation {
    public static let supportedAlgorithms = ["SHA1", "SHA256", "SHA512"]

    /// Normalise a typed secret: trim, drop spaces, uppercase.
    public static func normalizedSecret(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
    }

    /// Check an already-built entry (e.g. from `OtpauthUri.parse` or an import), returning it with
    /// a normalised secret and algorithm.
    public static func validated(_ entry: VaultEntryPlaintext) throws -> VaultEntryPlaintext {
        let secret = normalizedSecret(entry.secret)
        guard !secret.isEmpty else { throw EntryValidationError.secretRequired }
        guard let key = try? Base32.decode(secret), !key.isEmpty else { throw EntryValidationError.secretInvalid }
        guard (4...10).contains(entry.digits) else { throw EntryValidationError.digitsOutOfRange }
        guard entry.period > 0 else { throw EntryValidationError.periodInvalid }
        let algorithm = entry.algorithm.uppercased()
        guard supportedAlgorithms.contains(algorithm) else { throw EntryValidationError.algorithmUnsupported }
        var result = entry
        result.secret = secret
        result.algorithm = algorithm
        return result
    }

    /// An entry after the Edit screen: issuer and account are trimmed, a blank issuer becomes
    /// "Unknown" (as on Android), and everything else — secret, algorithm, digits, period, icon,
    /// id, order — is untouched.
    public static func edited(_ entry: VaultEntry, issuer: String, accountName: String) -> VaultEntry {
        var result = entry
        result.issuer = issuerOrUnknown(issuer)
        result.accountName = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }

    /// Build an entry from the manual-entry form fields (digits/period arrive as typed text).
    public static func manualEntry(
        issuer: String,
        accountName: String,
        secret: String,
        algorithm: String,
        digits: String,
        period: String,
        icon: String? = nil
    ) throws -> VaultEntryPlaintext {
        // A missing secret is reported first, as the form reads top-down.
        if normalizedSecret(secret).isEmpty { throw EntryValidationError.secretRequired }
        guard let d = Int(digits.trimmingCharacters(in: .whitespaces)), (4...10).contains(d) else {
            throw EntryValidationError.digitsOutOfRange
        }
        guard let p = Int(period.trimmingCharacters(in: .whitespaces)), p > 0 else {
            throw EntryValidationError.periodInvalid
        }
        return try validated(VaultEntryPlaintext(
            issuer: issuerOrUnknown(issuer),
            accountName: accountName.trimmingCharacters(in: .whitespacesAndNewlines),
            secret: secret,
            algorithm: algorithm,
            digits: d,
            period: p,
            icon: icon))
    }

    /// Trimmed, with a blank issuer becoming "Unknown" (as on Android).
    private static func issuerOrUnknown(_ issuer: String) -> String {
        let trimmed = issuer.trimmed
        return trimmed.isEmpty ? "Unknown" : trimmed
    }
}
