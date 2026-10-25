import Testing
@testable import PsTotpCore

/// Port of the Android `ServiceBrandsTest`, plus matching-order cases.
@Suite("ServiceBrands")
struct ServiceBrandsTests {
    @Test func blankOrNonAlphanumericIssuerReturnsNil() {
        #expect(ServiceBrands.get("") == nil)
        #expect(ServiceBrands.get("   ") == nil)
        #expect(ServiceBrands.get("🔒") == nil)
        #expect(ServiceBrands.get("---") == nil)
    }

    @Test func knownBrandFallsBackToFirstLetter() {
        #expect(ServiceBrands.get("GitHub")?.letter == "G")
        #expect(ServiceBrands.get("github")?.letter == "G")
    }

    @Test func presetLettersWin() {
        #expect(ServiceBrands.get("AWS Console")?.letter == "A")
        #expect(ServiceBrands.get("DigitalOcean")?.letter == "D")
        #expect(ServiceBrands.get("1Password")?.letter == "1")
    }

    @Test func matchesBothDirectionsAndIgnoresPunctuationAndCase() {
        // issuer contains brand name
        #expect(ServiceBrands.get("Google Workspace")?.bg == 0xFF4285F4)
        #expect(ServiceBrands.get("My-GitLab.com")?.bg == 0xFFFC6D26)
        // brand name contains issuer
        #expect(ServiceBrands.get("goog")?.bg == 0xFF4285F4)
    }

    @Test func firstMatchInTableOrderWins() {
        // "x" is contained in "dropbox" etc., but the single-letter brand comes first in the table.
        #expect(ServiceBrands.get("X")?.bg == 0xFF000000)
        // "Amazon Web Services" contains "amazon" before "aws" is considered.
        #expect(ServiceBrands.get("Amazon Web Services")?.bg == 0xFFFF9900)
    }

    @Test func unknownIssuerReturnsNil() {
        #expect(ServiceBrands.get("Totally Unknown Service") == nil)
    }
}
