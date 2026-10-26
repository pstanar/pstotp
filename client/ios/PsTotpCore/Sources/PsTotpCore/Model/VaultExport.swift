import CryptoKit
import Foundation

/// Vault export/import in multiple formats. Matches the web client's import-export.tsx and the
/// Android `VaultExport`.
///
/// `exportEncrypted` / `importEncrypted` run Argon2 (64 MB, ~100+ ms) synchronously: call them off
/// the main actor, as `VaultRepository` does for setup and unlock.
public enum VaultExport {
    public enum ImportResult: Equatable, Sendable {
        case success([VaultEntryPlaintext])
        case needsPassword
        case error(String)
    }

    public enum ExportError: Error, Equatable {
        case malformedEncryptedExport
        case wrongPasswordOrCorrupt
    }

    // MARK: Export

    /// Encrypted JSON: `{ version, format, salt, ciphertext, nonce }` (base64 fields).
    public static func exportEncrypted(entries: [VaultEntry], password: String) throws -> String {
        let plain = try JSONSerialization.data(withJSONObject: entriesToJson(entries), options: [.withoutEscapingSlashes])

        let salt = KeyDerivation.generateSalt()
        let encKey = try exportKey(password: password, salt: salt)
        let encrypted = try AesGcm.encrypt(key: encKey, plaintext: plain)

        let nonce = encrypted.prefix(AesGcm.nonceSize)
        let ciphertext = encrypted.dropFirst(AesGcm.nonceSize)

        return try serialize([
            "version": 1,
            "format": "pstotp-export",
            "salt": salt.base64EncodedString(),
            "ciphertext": Data(ciphertext).base64EncodedString(),
            "nonce": Data(nonce).base64EncodedString(),
        ])
    }

    /// Plain (unencrypted) JSON.
    public static func exportPlain(entries: [VaultEntry]) throws -> String {
        try serialize([
            "version": 1,
            "format": "pstotp-plain",
            "entries": entriesToJson(entries),
        ])
    }

    /// otpauth:// URIs, one per line.
    public static func exportOtpauthUris(entries: [VaultEntry]) -> String {
        entries.map { OtpauthUri.build($0.plaintext) }.joined(separator: "\n")
    }

    // MARK: Import

    /// Auto-detects otpauth:// lists, otpauth-migration:// (Google), pstotp-plain / pstotp-export,
    /// Aegis plain JSON and 2FAS JSON. Every entry is validated (see `EntryValidation`); the first
    /// one that couldn't produce codes fails the import.
    public static func importAutoDetect(_ content: String) -> ImportResult {
        switch parseAutoDetect(content) {
        case .success(let entries): validatedResult(entries)
        case let other: other
        }
    }

    private static func validatedResult(_ entries: [VaultEntryPlaintext]) -> ImportResult {
        var valid = [VaultEntryPlaintext]()
        for entry in entries {
            do { valid.append(try EntryValidation.validated(entry)) }
            catch { return .error("Invalid account \"\(entry.issuer)\": \(error)") }
        }
        return .success(valid)
    }

    private static func parseAutoDetect(_ content: String) -> ImportResult {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check migration first so it doesn't fall into the plain otpauth:// branch.
        if trimmed.hasPrefix("otpauth-migration://") {
            do {
                guard let entries = try ExternalImports.tryParseGoogleAuthMigration(trimmed) else {
                    return .error("Could not decode Google Authenticator export")
                }
                return entries.isEmpty ? .error("No TOTP accounts found in export") : .success(entries)
            } catch {
                return .error("Invalid Google Authenticator export: \(error)")
            }
        }

        if trimmed.hasPrefix("otpauth://") {
            do {
                let entries = try trimmed.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { $0.hasPrefix("otpauth://") }
                    .map(OtpauthUri.parse)
                return .success(entries)
            } catch {
                return .error("Invalid otpauth URI: \(error)")
            }
        }

        guard let json = (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) as? JSONObject else {
            return .error("Unrecognized file format")
        }
        let format = json.optString("format")

        if format == "pstotp-export" && json.has("ciphertext") { return .needsPassword }

        if format == "pstotp-plain", let array = json.optArray("entries") {
            do { return .success(try jsonArrayToPlaintexts(array)) }
            catch { return .error("Invalid PsTotp export: \(error)") }
        }

        if let entries = ExternalImports.tryParseAegis(json) { return .success(entries) }
        if let entries = ExternalImports.tryParse2Fas(json) { return .success(entries) }
        return .error("Unrecognized file format")
    }

    /// Import an encrypted export with its password. Throws `EntryValidationError` for an entry
    /// that couldn't produce codes.
    public static func importEncrypted(_ content: String, password: String) throws -> [VaultEntryPlaintext] {
        guard let json = (try? JSONSerialization.jsonObject(with: Data(content.utf8))) as? JSONObject,
              let saltB64 = json["salt"] as? String, let salt = Data(base64Encoded: saltB64),
              let ctB64 = json["ciphertext"] as? String, let ciphertext = Data(base64Encoded: ctB64),
              let nonceB64 = json["nonce"] as? String, let nonce = Data(base64Encoded: nonceB64)
        else { throw ExportError.malformedEncryptedExport }

        let encKey = try exportKey(password: password, salt: salt)

        let plain: Data
        do { plain = try AesGcm.decrypt(key: encKey, payload: nonce + ciphertext) }
        catch { throw ExportError.wrongPasswordOrCorrupt }

        guard let array = (try? JSONSerialization.jsonObject(with: plain)) as? [Any] else {
            throw ExportError.malformedEncryptedExport
        }
        return try jsonArrayToPlaintexts(array).map(EntryValidation.validated)
    }

    /// The same derivation as the vault's password envelope (Argon2id → HKDF), as on web/Android.
    private static func exportKey(password: String, salt: Data) throws -> Data {
        KeyDerivation.deriveEnvelopeKey(
            authKey: try KeyDerivation.derivePasswordAuthKey(password: password, salt: salt))
    }

    // MARK: JSON shape

    private static func serialize(_ object: JSONObject) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    private static func entriesToJson(_ entries: [VaultEntry]) -> [JSONObject] {
        entries.map(\.plaintext.jsonObject)
    }

    private static func jsonArrayToPlaintexts(_ array: [Any]) throws -> [VaultEntryPlaintext] {
        try array.map { element in
            guard let obj = element as? JSONObject, let plaintext = VaultEntryPlaintext(json: obj)
            else { throw ExportError.malformedEncryptedExport }
            return plaintext
        }
    }
}
