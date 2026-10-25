import Foundation
import Testing
@testable import PsTotpCore

@Suite("otpauth:// URIs")
struct OtpauthUriTests {

    @Test func parsesTypicalUri() throws {
        let e = try OtpauthUri.parse(
            "otpauth://totp/Example:alice@example.com?secret=jbswy3dpehpk3pxp&issuer=Example&algorithm=sha256&digits=8&period=60")
        #expect(e == VaultEntryPlaintext(
            issuer: "Example", accountName: "alice@example.com", secret: "JBSWY3DPEHPK3PXP",
            algorithm: "SHA256", digits: 8, period: 60))
    }

    @Test func appliesDefaults() throws {
        let e = try OtpauthUri.parse("otpauth://totp/alice?secret=JBSWY3DPEHPK3PXP")
        #expect(e.issuer == "")
        #expect(e.accountName == "alice")
        #expect(e.algorithm == "SHA1")
        #expect(e.digits == 6)
        #expect(e.period == 30)
    }

    @Test func splitsPercentEncodedLabelColon() throws {
        let e = try OtpauthUri.parse("otpauth://totp/GitHub%3Aoctocat?secret=JBSWY3DPEHPK3PXP")
        #expect(e.issuer == "GitHub")
        #expect(e.accountName == "octocat")
    }

    @Test func decodesQueryPlusAsSpaceAndStripsSecretSpaces() throws {
        let e = try OtpauthUri.parse("otpauth://totp/alice?secret=JBSW%20Y3DP+EHPK3PXP&issuer=My+Corp")
        #expect(e.secret == "JBSWY3DPEHPK3PXP")
        #expect(e.issuer == "My Corp")
    }

    @Test func rejectsInvalidUris() {
        #expect(throws: OtpauthError.notOtpauth) { try OtpauthUri.parse("https://example.com") }
        #expect(throws: OtpauthError.unsupportedType) { try OtpauthUri.parse("otpauth://hotp/a?secret=JBSW&counter=1") }
        #expect(throws: OtpauthError.missingSecret) { try OtpauthUri.parse("otpauth://totp/a") }
        #expect(throws: OtpauthError.unsupportedAlgorithm("MD5")) { try OtpauthUri.parse("otpauth://totp/a?secret=JBSW&algorithm=md5") }
        #expect(throws: OtpauthError.digitsOutOfRange) { try OtpauthUri.parse("otpauth://totp/a?secret=JBSW&digits=3") }
        #expect(throws: OtpauthError.digitsOutOfRange) { try OtpauthUri.parse("otpauth://totp/a?secret=JBSW&digits=11") }
        #expect(throws: OtpauthError.invalidPeriod) { try OtpauthUri.parse("otpauth://totp/a?secret=JBSW&period=0") }
    }

    @Test func buildProducesExpectedUri() {
        let uri = OtpauthUri.build(VaultEntryPlaintext(
            issuer: "My Corp", accountName: "bob@x.io", secret: "JBSWY3DPEHPK3PXP",
            algorithm: "SHA512", digits: 8, period: 45))
        #expect(uri == "otpauth://totp/bob%40x.io?secret=JBSWY3DPEHPK3PXP&issuer=My%20Corp&algorithm=SHA512&digits=8&period=45")
    }

    @Test func buildOmitsEmptyIssuer() {
        let uri = OtpauthUri.build(VaultEntryPlaintext(issuer: "", accountName: "a", secret: "JBSW"))
        #expect(!uri.contains("issuer"))
    }

    @Test func keepsColonInAccountNameWhenIssuerIsAQueryParam() throws {
        let parsed = try OtpauthUri.parse(OtpauthUri.build(
            VaultEntryPlaintext(issuer: "Corp", accountName: "bob: work", secret: "JBSW")))
        #expect(parsed.issuer == "Corp")
        #expect(parsed.accountName == "bob: work")
    }

    @Test(arguments: ["bob: work", "a:b:c", "https://example.com:8080", ":leading", "trailing:"])
    func roundTripsAccountNamesContainingColons(account: String) throws {
        let parsed = try OtpauthUri.parse(OtpauthUri.build(
            VaultEntryPlaintext(issuer: "Corp", accountName: account, secret: "JBSW")))
        #expect(parsed.issuer == "Corp")
        #expect(parsed.accountName == account)
    }

    @Test(arguments: ["Corp:bob", "Corp%3Abob", "corp:bob", "Corp: bob"])
    func stripsRedundantIssuerPrefix(label: String) throws {
        let parsed = try OtpauthUri.parse("otpauth://totp/\(label)?secret=JBSW&issuer=Corp")
        #expect(parsed.issuer == "Corp")
        #expect(parsed.accountName == "bob")
    }

    @Test func keepsWholeLabelWhenPrefixIsNotTheIssuer() throws {
        let parsed = try OtpauthUri.parse("otpauth://totp/Old:alice?secret=JBSW&issuer=New")
        #expect(parsed.issuer == "New")
        #expect(parsed.accountName == "Old:alice")
    }

    @Test func labelResolutionWithoutIssuerParam() {
        #expect(OtpauthUri.resolveLabel("GitHub:octocat", queryIssuer: nil) == ("GitHub", "octocat"))
        #expect(OtpauthUri.resolveLabel("GitHub: octocat:x", queryIssuer: nil) == ("GitHub", "octocat:x"))
        #expect(OtpauthUri.resolveLabel("octocat", queryIssuer: nil) == ("", "octocat"))
        // A blank issuer param counts as absent.
        #expect(OtpauthUri.resolveLabel("GitHub:octocat", queryIssuer: "") == ("GitHub", "octocat"))
        #expect(OtpauthUri.resolveLabel("GitHub:octocat", queryIssuer: "  ") == ("GitHub", "octocat"))
    }

    @Test(arguments: [
        VaultEntryPlaintext(issuer: "Example", accountName: "alice@example.com", secret: "JBSWY3DPEHPK3PXP"),
        VaultEntryPlaintext(issuer: "Bank/Corp & Co", accountName: "bob: work+test", secret: "NBSWY3DPFQQHO33SNRSCC",
                            algorithm: "SHA256", digits: 8, period: 60),
        VaultEntryPlaintext(issuer: "日本語 🔑", accountName: "ünïcode", secret: "JBSWY3DPEHPK3PXP"),
        VaultEntryPlaintext(issuer: "", accountName: "no-issuer", secret: "JBSWY3DPEHPK3PXP"),
    ])
    func buildThenParseRoundTrips(entry: VaultEntryPlaintext) throws {
        #expect(try OtpauthUri.parse(OtpauthUri.build(entry)) == entry)
    }
}
