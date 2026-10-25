import Foundation
import Testing
@testable import PsTotpCore

/// Port of the Android `ExternalImportsTest`.
@Suite("External imports")
struct ExternalImportsTests {

    // MARK: Google Authenticator

    @Test func googleMigrationDecodesBothEntries() throws {
        let secret1 = try Base32.decode("JBSWY3DPEHPK3PXP")
        let secret2 = try Base32.decode("NBSWY3DPFQQHO33SNRSCC")

        let otp1 = ProtoBuilder()
            .bytes(1, secret1).string(2, "alice@example.com").string(3, "Example")
            .varint(4, 1).varint(5, 1).varint(6, 2).build()
        let otp2 = ProtoBuilder()
            .bytes(1, secret2).string(2, "bob").string(3, "")
            .varint(4, 2).varint(5, 2).varint(6, 2).build()
        let payload = ProtoBuilder().bytes(1, otp1).bytes(1, otp2).varint(2, 1).build()

        let entries = try #require(try ExternalImports.tryParseGoogleAuthMigration(migrationUri(payload)))
        #expect(entries.count == 2)
        #expect(entries[0].issuer == "Example")
        #expect(entries[0].accountName == "alice@example.com")
        #expect(entries[0].secret == Base32.encode(secret1))
        #expect(entries[0].algorithm == "SHA1")
        #expect(entries[0].digits == 6)
        #expect(entries[1].accountName == "bob")
        #expect(entries[1].issuer == "Unknown")
        #expect(entries[1].secret == Base32.encode(secret2))
        #expect(entries[1].algorithm == "SHA256")
        #expect(entries[1].digits == 8)
    }

    @Test func googleSplitsIssuerAccountInNameField() throws {
        let entries = try googleEntries(name: "GitHub:octocat", issuer: "")
        #expect(entries[0].issuer == "GitHub")
        #expect(entries[0].accountName == "octocat")
    }

    @Test func googleStripsRedundantIssuerPrefix() throws {
        let entries = try googleEntries(name: "GitHub:octocat", issuer: "GitHub")
        #expect(entries[0].issuer == "GitHub")
        #expect(entries[0].accountName == "octocat")
    }

    @Test func googleKeepsColonsWhenPrefixDoesNotMatchIssuer() throws {
        let entries = try googleEntries(name: "work:alice", issuer: "Company")
        #expect(entries[0].issuer == "Company")
        #expect(entries[0].accountName == "work:alice")
    }

    @Test func googleSkipsHotp() throws {
        let otp = ProtoBuilder()
            .bytes(1, try Base32.decode("JBSWY3DPEHPK3PXP")).string(2, "counter-based").string(3, "Bank")
            .varint(4, 1).varint(5, 1).varint(6, 1).build()
        let payload = ProtoBuilder().bytes(1, otp).build()
        #expect(try ExternalImports.tryParseGoogleAuthMigration(migrationUri(payload))?.isEmpty == true)
    }

    @Test func googleReturnsNilForOtherSchemes() throws {
        #expect(try ExternalImports.tryParseGoogleAuthMigration("otpauth://totp/foo?secret=JBSW") == nil)
        #expect(try ExternalImports.tryParseGoogleAuthMigration("https://example.com") == nil)
    }

    @Test func googleThrowsOnCorruptPayload() {
        // Length-delimited field claiming 100 bytes with none following.
        let bad = Data([0x0A, 0x64])
        #expect(throws: ImportParseError.badLengthDelimited) {
            try ExternalImports.tryParseGoogleAuthMigration(migrationUri(bad))
        }
        #expect(throws: ImportParseError.invalidBase64) {
            try ExternalImports.tryParseGoogleAuthMigration("otpauth-migration://offline?data=!!!not-base64!!!")
        }
    }

    // MARK: Aegis

    @Test func aegisPlainExportParses() throws {
        let json = try object("""
        { "version": 1, "header": { "slots": null, "params": null },
          "db": { "version": 3, "entries": [
            { "type": "totp", "name": "alice@example.com", "issuer": "Example",
              "info": { "secret": "jbswy3dpehpk3pxp", "algo": "sha1", "digits": 6, "period": 30 } },
            { "type": "hotp", "name": "counter", "issuer": "Bank",
              "info": { "secret": "NBSWY3DPFQQHO33SNRSCC", "algo": "SHA1", "digits": 6, "counter": 0 } }
          ] } }
        """)
        let entries = try #require(ExternalImports.tryParseAegis(json))
        #expect(entries.count == 1)
        #expect(entries[0].issuer == "Example")
        #expect(entries[0].accountName == "alice@example.com")
        #expect(entries[0].secret == "JBSWY3DPEHPK3PXP")
        #expect(entries[0].algorithm == "SHA1")
    }

    @Test func aegisExtractsEmbeddedIconAndDefaultsMime() throws {
        let withMime = try object("""
        { "version":1, "header":{}, "db": { "entries": [ { "type":"totp","name":"a","issuer":"E",
          "icon":"aGVsbG8=", "icon_mime":"image/svg+xml", "info": { "secret":"jbswy3dpehpk3pxp" } } ] } }
        """)
        #expect(ExternalImports.tryParseAegis(withMime)?[0].icon == "data:image/svg+xml;base64,aGVsbG8=")

        let withoutMime = try object("""
        { "version":1, "header":{}, "db": { "entries": [ { "type":"totp","name":"a","issuer":"E",
          "icon":"aGVsbG8=", "info": { "secret":"jbswy3dpehpk3pxp" } } ] } }
        """)
        #expect(ExternalImports.tryParseAegis(withoutMime)?[0].icon == "data:image/png;base64,aGVsbG8=")

        let noIcon = try object("""
        { "version":1, "header":{}, "db": { "entries": [ { "type":"totp","name":"a","issuer":"E",
          "info": { "secret":"jbswy3dpehpk3pxp" } } ] } }
        """)
        #expect(ExternalImports.tryParseAegis(noIcon)?[0].icon == nil)
    }

    @Test func aegisRejectsShapeWithoutHeader() throws {
        let json = try object(#"{ "db": { "entries": [ { "type": "totp", "info": { "secret": "X" } } ] } }"#)
        #expect(ExternalImports.tryParseAegis(json) == nil)
    }

    // MARK: 2FAS

    @Test func twoFasExportParses() throws {
        let json = try object("""
        { "schemaVersion": 4, "appVersionCode": 500000, "services": [ {
            "secret": "JBSWY3DPEHPK3PXP", "name": "Example",
            "otp": { "account": "alice@example.com", "issuer": "Example",
                     "digits": 6, "period": 30, "algorithm": "SHA1" } } ] }
        """)
        let entries = try #require(ExternalImports.tryParse2Fas(json))
        #expect(entries.count == 1)
        #expect(entries[0].issuer == "Example")
        #expect(entries[0].accountName == "alice@example.com")
        #expect(entries[0].secret == "JBSWY3DPEHPK3PXP")
    }

    @Test func twoFasFallsBackToNameWhenOtpAccountMissing() throws {
        let json = try object(#"{ "schemaVersion": 3, "services": [ { "secret": "JBSWY3DPEHPK3PXP", "name": "Legacy Service" } ] }"#)
        let entries = try #require(ExternalImports.tryParse2Fas(json))
        #expect(entries[0].issuer == "Legacy Service")
        #expect(entries[0].accountName == "Legacy Service")
    }

    @Test func twoFasIgnoresBrandIdIconsButKeepsEmbeddedImages() throws {
        let brandRef = try object("""
        { "schemaVersion":4, "services": [ { "secret":"JBSWY3DPEHPK3PXP","name":"Example",
          "icon": { "selected": "Brand", "brand": { "id": "github" } } } ] }
        """)
        #expect(ExternalImports.tryParse2Fas(brandRef)?[0].icon == nil)

        let embedded = try object(#"{ "schemaVersion":4, "services": [ { "secret":"JBSWY3DPEHPK3PXP","name":"Example","icon":"aGVsbG8=" } ] }"#)
        #expect(ExternalImports.tryParse2Fas(embedded)?[0].icon == "data:image/png;base64,aGVsbG8=")
    }

    @Test func twoFasRejectsShapeWithoutSchemaVersion() throws {
        #expect(ExternalImports.tryParse2Fas(try object(#"{ "services": [ { "secret": "X" } ] }"#)) == nil)
    }

    // MARK: Helpers

    private func object(_ json: String) throws -> JSONObject {
        try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? JSONObject)
    }

    private func googleEntries(name: String, issuer: String) throws -> [VaultEntryPlaintext] {
        let otp = ProtoBuilder()
            .bytes(1, try Base32.decode("JBSWY3DPEHPK3PXP")).string(2, name).string(3, issuer)
            .varint(4, 1).varint(5, 1).varint(6, 2).build()
        let payload = ProtoBuilder().bytes(1, otp).build()
        return try #require(try ExternalImports.tryParseGoogleAuthMigration(migrationUri(payload)))
    }

    private func migrationUri(_ payload: Data) -> String {
        "otpauth-migration://offline?data=" + payload.base64EncodedString()
    }
}

/// Tiny protobuf builder used by the tests.
struct ProtoBuilder {
    private var out = Data()

    func varint(_ field: Int, _ value: Int) -> ProtoBuilder {
        var b = self
        b.writeVarint(UInt64(field << 3))
        b.writeVarint(UInt64(value))
        return b
    }

    func bytes(_ field: Int, _ value: Data) -> ProtoBuilder {
        var b = self
        b.writeVarint(UInt64((field << 3) | 2))
        b.writeVarint(UInt64(value.count))
        b.out.append(value)
        return b
    }

    func string(_ field: Int, _ value: String) -> ProtoBuilder { bytes(field, Data(value.utf8)) }

    func build() -> Data { out }

    private mutating func writeVarint(_ v: UInt64) {
        var value = v
        while value & ~0x7F != 0 {
            out.append(UInt8((value & 0x7F) | 0x80))
            value >>= 7
        }
        out.append(UInt8(value))
    }
}
