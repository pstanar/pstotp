import Foundation

public enum EntryValidationError: Error, Equatable, CustomStringConvertible {
    case secretRequired
    case secretInvalid
    case digitsOutOfRange
    case periodInvalid

    public var description: String {
        switch self {
        case .secretRequired: "Secret key is required"
        case .secretInvalid: "Secret key is not valid Base32"
        case .digitsOutOfRange: "Digits must be between 4 and 10"
        case .periodInvalid: "Period must be a positive number"
        }
    }
}

/// Validation for new entries, whether typed in or parsed from an otpauth:// URI.
///
/// Android's manual form accepts any secret and the card then fails when it generates a code;
/// iOS rejects a secret that isn't decodable Base32 up front.
public enum EntryValidation {

    /// Normalise a typed secret: trim, drop spaces, uppercase.
    public static func normalizedSecret(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
    }

    /// Check an already-built entry (e.g. from `OtpauthUri.parse`), returning it with a normalised secret.
    public static func validated(_ entry: VaultEntryPlaintext) throws -> VaultEntryPlaintext {
        let secret = normalizedSecret(entry.secret)
        guard !secret.isEmpty else { throw EntryValidationError.secretRequired }
        guard let key = try? Base32.decode(secret), !key.isEmpty else { throw EntryValidationError.secretInvalid }
        guard (4...10).contains(entry.digits) else { throw EntryValidationError.digitsOutOfRange }
        guard entry.period > 0 else { throw EntryValidationError.periodInvalid }
        var result = entry
        result.secret = secret
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
        guard let d = Int(digits.trimmingCharacters(in: .whitespaces)), (4...10).contains(d) else {
            // Validate the secret first when it is the thing that's missing, as the form reads top-down.
            if normalizedSecret(secret).isEmpty { throw EntryValidationError.secretRequired }
            throw EntryValidationError.digitsOutOfRange
        }
        guard let p = Int(period.trimmingCharacters(in: .whitespaces)), p > 0 else {
            if normalizedSecret(secret).isEmpty { throw EntryValidationError.secretRequired }
            throw EntryValidationError.periodInvalid
        }
        let trimmedIssuer = issuer.trimmingCharacters(in: .whitespacesAndNewlines)
        return try validated(VaultEntryPlaintext(
            issuer: trimmedIssuer.isEmpty ? "Unknown" : trimmedIssuer,
            accountName: accountName.trimmingCharacters(in: .whitespacesAndNewlines),
            secret: secret,
            algorithm: algorithm,
            digits: d,
            period: p,
            icon: icon))
    }
}
