import Foundation
import Testing
@testable import PsTotpCore

@Suite("Import plan & export format")
struct ImportPlanTests {
    private func existing(_ id: String, _ issuer: String, _ account: String, sortOrder: Int = 0) -> VaultEntry {
        VaultEntry(id: id, issuer: issuer, accountName: account, secret: "JBSWY3DPEHPK3PXP", version: 4, sortOrder: sortOrder)
    }

    private func imported(_ issuer: String, _ account: String, secret: String = "GEZDGNBVGY3TQOJQ") -> VaultEntryPlaintext {
        VaultEntryPlaintext(issuer: issuer, accountName: account, secret: secret, digits: 8, icon: "🔑")
    }

    @Test func overwriteKeepsIdentityAndReplacesEveryImportedField() throws {
        let vault = [existing("a", "GitHub", "octocat", sortOrder: 7)]
        let candidates = ImportCandidate.buildCandidates(imported: [imported("github", "OCTOCAT")], existing: vault)
        let plan = ImportCandidate.plan(candidates, existing: vault)

        #expect(plan.additions.isEmpty)
        let updated = try #require(plan.updates.first)
        #expect(updated.id == "a" && updated.version == 4 && updated.sortOrder == 7)
        #expect(updated.plaintext == imported("github", "OCTOCAT"))
    }

    @Test func addCopyDeduplicatesAgainstVaultAndEarlierAdditions() {
        let vault = [existing("a", "GitHub", "octocat")]
        var candidates = ImportCandidate.buildCandidates(
            imported: [imported("GitHub", "octocat"), imported("GitHub", "octocat"), imported("AWS", "root")],
            existing: vault)
        candidates = ImportCandidate.settingDuplicateAction(.addCopy, in: candidates)
        let plan = ImportCandidate.plan(candidates, existing: vault)

        #expect(plan.updates.isEmpty)
        #expect(plan.additions.map(\.accountName) == ["octocat (2)", "octocat (3)", "root"])
        #expect(plan.count == 3)
    }

    @Test func newEntriesKeepTheirNameEvenIfAnEarlierAdditionTookIt() {
        // Matches Android: only duplicates of the *vault* are renamed.
        let candidates = ImportCandidate.buildCandidates(
            imported: [imported("AWS", "root"), imported("AWS", "root")], existing: [])
        #expect(ImportCandidate.plan(candidates, existing: []).additions.map(\.accountName) == ["root", "root"])
    }

    @Test func skipDropsTheCandidateAndSettingDuplicateActionLeavesNewOnesAlone() {
        let vault = [existing("a", "GitHub", "octocat")]
        var candidates = ImportCandidate.buildCandidates(
            imported: [imported("GitHub", "octocat"), imported("AWS", "root")], existing: vault)
        candidates = ImportCandidate.settingDuplicateAction(.skip, in: candidates)
        #expect(candidates.map(\.action) == [.skip, .addCopy])

        let plan = ImportCandidate.plan(candidates, existing: vault)
        #expect(plan.updates.isEmpty)
        #expect(plan.additions.map(\.issuer) == ["AWS"])
    }

    @Test func exportFormatsMatchAndroid() throws {
        #expect(ExportFormat.allCases.map(\.label) == ["Encrypted", "Plain JSON", "otpauth:// URIs"])
        #expect(ExportFormat.allCases.map(\.fileName) == ["pstotp-export.json", "pstotp-export.json", "pstotp-export.txt"])
        #expect(ExportFormat.allCases.map(\.revealsSecrets) == [false, true, true])

        let entries = [existing("a", "GitHub", "octocat")]
        let otpauth = try ExportFormat.otpauth.export(entries: entries, password: "")
        #expect(otpauth.hasPrefix("otpauth://totp/"))
        let plain = try ExportFormat.plain.export(entries: entries, password: "")
        guard case .success(let back) = VaultExport.importAutoDetect(plain) else { Issue.record(); return }
        #expect(back == entries.map(\.plaintext))
    }

    @Test func encryptedExportRoundTripsWithItsPassword() throws {
        let entries = [existing("a", "GitHub", "octocat")]
        let file = try ExportFormat.encrypted.export(entries: entries, password: "pw")
        #expect(VaultExport.importAutoDetect(file) == .needsPassword)
        #expect(try VaultExport.importEncrypted(file, password: "pw") == entries.map(\.plaintext))
        #expect(throws: VaultExport.ExportError.wrongPasswordOrCorrupt) {
            try VaultExport.importEncrypted(file, password: "nope")
        }
    }
}
