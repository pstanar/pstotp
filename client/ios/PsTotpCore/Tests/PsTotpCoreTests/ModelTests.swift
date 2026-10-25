import Foundation
import Testing
@testable import PsTotpCore

@Suite("Models")
struct ModelTests {
    private func entry(_ issuer: String, _ account: String) -> VaultEntry {
        VaultEntry(id: UUID().uuidString, issuer: issuer, accountName: account, secret: "JBSWY3DPEHPK3PXP")
    }

    @Test func candidatesMatchCaseInsensitively() {
        let existing = [entry("GitHub", "Octocat")]
        let imported = [
            VaultEntryPlaintext(issuer: "github", accountName: "OCTOCAT", secret: "X"),
            VaultEntryPlaintext(issuer: "GitHub", accountName: "other", secret: "Y"),
        ]
        let c = ImportCandidate.buildCandidates(imported: imported, existing: existing)
        #expect(c[0].isDuplicate && c[0].action == .overwrite)
        #expect(!c[1].isDuplicate && c[1].action == .addCopy)
    }

    @Test func makeUniqueNameAppendsCounter() {
        let existing = [entry("GitHub", "octocat"), entry("GitHub", "octocat (2)"), entry("Other", "solo")]
        #expect(ImportCandidate.makeUniqueName("octocat", issuer: "github", existing: existing) == "octocat (3)")
        #expect(ImportCandidate.makeUniqueName("fresh", issuer: "GitHub", existing: existing) == "fresh")
        #expect(ImportCandidate.makeUniqueName("solo", issuer: "GitHub", existing: existing) == "solo")
    }

    @Test func storageKeysFallBackToDefaults() {
        #expect(SortMode.fromStorageKey("mfu") == .mfu)
        #expect(SortMode.fromStorageKey("bogus") == .manual)
        #expect(SortMode.fromStorageKey(nil) == .manual)
        #expect(LayoutMode.fromStorageKey("grid") == .grid)
        #expect(LayoutMode.fromStorageKey("bogus") == .list)
    }

    @Test func lockTimeoutLookup() {
        #expect(LockTimeout.fromMillis(60_000) == .oneMinute)
        #expect(LockTimeout.fromMillis(Int64.max) == .never)
        #expect(LockTimeout.fromMillis(12345) == .fiveMinutes)
        #expect(LockTimeout.fromMillis(nil, default: .oneHour) == .oneHour)
    }

    @Test func vaultEntryPlaintextCodableOmitsNilIcon() throws {
        let p = VaultEntryPlaintext(issuer: "I", accountName: "A", secret: "S")
        let data = try JSONEncoder().encode(p)
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? JSONObject)
        #expect(obj["icon"] == nil)
        #expect(try JSONDecoder().decode(VaultEntryPlaintext.self, from: data) == p)
    }
}
