import Foundation
import Testing
@testable import PsTotpCore

@Suite("Vault export / import")
struct VaultExportTests {
    let fixtures = Vectors.shared.exportFixtures

    private let entries = [
        VaultEntry(id: "1", issuer: "Example", accountName: "alice@example.com", secret: "JBSWY3DPEHPK3PXP"),
        VaultEntry(id: "2", issuer: "Bank/Corp", accountName: "bob: work", secret: "NBSWY3DPFQQHO33SNRSCC",
                   algorithm: "SHA256", digits: 8, period: 60, icon: "🏦"),
    ]

    private var plaintexts: [VaultEntryPlaintext] {
        entries.map { VaultEntryPlaintext(issuer: $0.issuer, accountName: $0.accountName, secret: $0.secret,
                                          algorithm: $0.algorithm, digits: $0.digits, period: $0.period, icon: $0.icon) }
    }

    // MARK: Interop with the web client format

    @Test func decryptsExportProducedOutsideSwift() throws {
        let export = fixtures.encryptedExport
        let json = try String(decoding: JSONEncoder().encode(Wrapper(export)), as: UTF8.self)
        #expect(VaultExport.importAutoDetect(json) == .needsPassword)

        let imported = try VaultExport.importEncrypted(json, password: fixtures.password)
        let expected = fixtures.entries.map {
            VaultEntryPlaintext(issuer: $0.issuer, accountName: $0.accountName, secret: $0.secret,
                                algorithm: $0.algorithm, digits: $0.digits, period: $0.period, icon: $0.icon)
        }
        #expect(imported == expected)
    }

    @Test func importsGoogleMigrationUriWithPercentEncodedPadding() throws {
        guard case .success(let entries) = VaultExport.importAutoDetect(fixtures.googleMigrationUri) else {
            Issue.record("expected success"); return
        }
        #expect(entries.count == 2)
        #expect(entries[0] == VaultEntryPlaintext(issuer: "Example", accountName: "alice@example.com",
                                                  secret: "JBSWY3DPEHPK3PXP"))
        #expect(entries[1].accountName == "bob")
        #expect(entries[1].algorithm == "SHA256")
        #expect(entries[1].digits == 8)
    }

    // MARK: Round trips

    @Test func encryptedExportRoundTrips() throws {
        let json = try VaultExport.exportEncrypted(entries: entries, password: "s3cret-pässword")
        #expect(VaultExport.importAutoDetect(json) == .needsPassword)
        #expect(try VaultExport.importEncrypted(json, password: "s3cret-pässword") == plaintexts)
    }

    @Test func encryptedExportHasExpectedEnvelope() throws {
        let json = try VaultExport.exportEncrypted(entries: entries, password: "pw-pw-pw-pw")
        let obj = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? JSONObject)
        #expect(obj["format"] as? String == "pstotp-export")
        #expect(obj["version"] as? Int == 1)
        #expect(Data(base64Encoded: try #require(obj["salt"] as? String))?.count == 16)
        #expect(Data(base64Encoded: try #require(obj["nonce"] as? String))?.count == 12)
    }

    @Test func wrongPasswordIsRejected() throws {
        let json = try VaultExport.exportEncrypted(entries: entries, password: "right-password")
        #expect(throws: VaultExport.ExportError.wrongPasswordOrCorrupt) {
            try VaultExport.importEncrypted(json, password: "wrong-password")
        }
    }

    @Test func malformedEncryptedExportIsRejected() {
        #expect(throws: VaultExport.ExportError.malformedEncryptedExport) {
            try VaultExport.importEncrypted(#"{"format":"pstotp-export"}"#, password: "x")
        }
    }

    @Test func plainExportRoundTrips() throws {
        let json = try VaultExport.exportPlain(entries: entries)
        #expect(VaultExport.importAutoDetect(json) == .success(plaintexts))
    }

    @Test func otpauthExportRoundTrips() {
        // Icons are not part of the otpauth:// format.
        let simple = [
            VaultEntry(id: "1", issuer: "Example", accountName: "alice@example.com", secret: "JBSWY3DPEHPK3PXP"),
            VaultEntry(id: "2", issuer: "Bank/Corp", accountName: "bob: work", secret: "NBSWY3DPFQQHO33SNRSCC",
                       algorithm: "SHA256", digits: 8, period: 60, icon: "🏦"),
        ]
        let text = VaultExport.exportOtpauthUris(entries: simple)
        #expect(text.split(separator: "\n").count == 2)
        let expected = simple.map {
            VaultEntryPlaintext(issuer: $0.issuer, accountName: $0.accountName, secret: $0.secret,
                                algorithm: $0.algorithm, digits: $0.digits, period: $0.period)
        }
        #expect(VaultExport.importAutoDetect(text) == .success(expected))
    }

    @Test func uriListIsDetectedByLeadingUriOnly() {
        // Same as Android: blank lines between URIs are fine, a leading non-URI line is not.
        let uri = "otpauth://totp/a?secret=JBSWY3DPEHPK3PXP"
        #expect(VaultExport.importAutoDetect("\n\(uri)\n\n\(uri)\n").isSuccessCount(2))
        #expect(VaultExport.importAutoDetect("# comment\n\(uri)") == .error("Unrecognized file format"))
    }

    // MARK: Auto-detect

    @Test func autoDetectErrors() {
        #expect(VaultExport.importAutoDetect("hello world") == .error("Unrecognized file format"))
        #expect(VaultExport.importAutoDetect(#"{"foo":1}"#) == .error("Unrecognized file format"))
        guard case .error(let msg) = VaultExport.importAutoDetect("otpauth://totp/a") else {
            Issue.record("expected error"); return
        }
        #expect(msg.contains("Missing secret"))
        guard case .error(let google) = VaultExport.importAutoDetect("otpauth-migration://offline") else {
            Issue.record("expected error"); return
        }
        #expect(google == "Could not decode Google Authenticator export")
    }

    @Test func autoDetectsAegisAnd2Fas() {
        let aegis = #"{"version":1,"header":{},"db":{"entries":[{"type":"totp","name":"a","issuer":"E","info":{"secret":"jbswy3dpehpk3pxp"}}]}}"#
        #expect(VaultExport.importAutoDetect(aegis) == .success([
            VaultEntryPlaintext(issuer: "E", accountName: "a", secret: "JBSWY3DPEHPK3PXP")]))
        let twoFas = #"{"schemaVersion":4,"services":[{"secret":"JBSWY3DPEHPK3PXP","name":"N"}]}"#
        #expect(VaultExport.importAutoDetect(twoFas) == .success([
            VaultEntryPlaintext(issuer: "N", accountName: "N", secret: "JBSWY3DPEHPK3PXP")]))
    }

    // MARK: Validation of imported entries

    @Test func importRejectsEntriesThatCannotProduceCodes() {
        let zeroPeriod = #"{"version":1,"header":{},"db":{"entries":[{"type":"totp","name":"a","issuer":"E","info":{"secret":"JBSWY3DPEHPK3PXP","period":0}}]}}"#
        #expect(VaultExport.importAutoDetect(zeroPeriod) == .error("Invalid account \"E\": Period must be a positive number"))

        let badSecret = #"{"format":"pstotp-plain","entries":[{"issuer":"E","accountName":"a","secret":"not base32!"}]}"#
        #expect(VaultExport.importAutoDetect(badSecret) == .error("Invalid account \"E\": Secret key is not valid Base32"))

        let badAlgorithm = #"{"schemaVersion":4,"services":[{"secret":"JBSWY3DPEHPK3PXP","name":"N","otp":{"algorithm":"MD5"}}]}"#
        #expect(VaultExport.importAutoDetect(badAlgorithm) == .error("Invalid account \"N\": Unsupported algorithm"))

        let badUri = "otpauth://totp/a?secret=!!!!&issuer=E"
        #expect(VaultExport.importAutoDetect(badUri) == .error("Invalid account \"E\": Secret key is not valid Base32"))
    }

    @Test func importNormalisesSecrets() {
        let spaced = #"{"format":"pstotp-plain","entries":[{"issuer":"E","accountName":"a","secret":"jbsw y3dp ehpk 3pxp"}]}"#
        #expect(VaultExport.importAutoDetect(spaced) == .success([
            VaultEntryPlaintext(issuer: "E", accountName: "a", secret: "JBSWY3DPEHPK3PXP")]))
    }

    @Test func encryptedImportRejectsInvalidEntries() throws {
        let bad = [VaultEntry(id: "1", issuer: "E", accountName: "a", secret: "JBSWY3DPEHPK3PXP", period: 0)]
        let json = try VaultExport.exportEncrypted(entries: bad, password: "pw")
        #expect(throws: EntryValidationError.periodInvalid) { try VaultExport.importEncrypted(json, password: "pw") }
    }

    /// The vault payload and the export share one JSON shape, so an empty icon means "no icon" in both.
    @Test func emptyIconImportsAsNoIcon() {
        let json = #"{"format":"pstotp-plain","entries":[{"issuer":"E","accountName":"a","secret":"JBSWY3DPEHPK3PXP","icon":""}]}"#
        #expect(VaultExport.importAutoDetect(json) == .success([
            VaultEntryPlaintext(issuer: "E", accountName: "a", secret: "JBSWY3DPEHPK3PXP", icon: nil)]))
    }

    private struct Wrapper: Encodable {
        let version: Int, format: String, salt: String, ciphertext: String, nonce: String
        init(_ e: Vectors.EncryptedExport) {
            version = e.version; format = e.format; salt = e.salt; ciphertext = e.ciphertext; nonce = e.nonce
        }
    }
}

private extension VaultExport.ImportResult {
    func isSuccessCount(_ n: Int) -> Bool {
        if case .success(let entries) = self { return entries.count == n }
        return false
    }
}
