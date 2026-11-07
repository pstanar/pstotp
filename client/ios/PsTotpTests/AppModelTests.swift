import Foundation
import PsTotpCore
import SwiftUI
import UIKit
import Testing
@testable import PsTotp

@MainActor
@Suite("AppModel")
struct AppModelTests {
    let db: AppDatabase
    let biometrics = FakeBiometrics()

    init() throws { db = try AppDatabase.inMemory() }

    private func makeModel() -> AppModel { AppModel(repository: VaultRepository(db: db), iconLibrary: IconLibraryRepository(db: db), biometrics: biometrics) }

    private func started() async -> AppModel {
        let model = makeModel()
        await model.start()
        return model
    }

    private let strong = "Str0ng!Passw0rd"

    private func plain(_ issuer: String, account: String = "me", secret: String = "JBSWY3DPEHPK3PXP") -> VaultEntryPlaintext {
        VaultEntryPlaintext(issuer: issuer, accountName: account, secret: secret)
    }

    // MARK: Phases

    @Test func freshInstallNeedsSetupThenUnlocksAndNextLaunchIsLocked() async throws {
        let first = await started()
        #expect(first.phase == .needsSetup)
        #expect(await first.setupPassword(strong, confirm: strong))
        #expect(first.phase == .unlocked)

        let relaunch = await started()          // same database, new process
        #expect(relaunch.phase == .locked)
    }

    @Test func weakPasswordIsRejectedWithoutCreatingAVault() async {
        let model = await started()
        #expect(await model.setupPassword("short", confirm: "short") == false)
        #expect(model.errorMessage == "Password must be at least 8 characters")
        #expect(await model.setupPassword(strong, confirm: "different") == false)
        #expect(model.errorMessage == "Passwords do not match")
        #expect(model.phase == .needsSetup)
        #expect(await started().phase == .needsSetup)
    }

    @Test func wrongPasswordStaysLockedRightPasswordRestoresEntries() async {
        let setup = await started()
        _ = await setup.setupPassword(strong, confirm: strong)
        #expect(await setup.addEntry(plain("GitHub")) == nil)

        let model = await started()
        #expect(await model.unlock(password: "wrong") == false)
        #expect(model.errorMessage == "Incorrect password")
        #expect(model.phase == .locked)
        #expect(model.entries.isEmpty)

        #expect(await model.unlock(password: strong))
        #expect(model.errorMessage == nil)
        #expect(model.phase == .unlocked)
        #expect(model.entries.map(\.issuer) == ["GitHub"])
    }

    @Test func lockClearsDecryptedEntries() async {
        let model = await started()
        _ = await model.setupPassword(strong, confirm: strong)
        _ = await model.addEntry(plain("GitHub"))
        model.lock()
        #expect(model.phase == .locked)
        #expect(model.entries.isEmpty)
        #expect(await model.addEntry(plain("Other")) == "Vault is locked")
    }

    // MARK: Entries

    @Test func addRejectsAnInvalidSecretWithoutStoringIt() async {
        let model = await started()
        _ = await model.setupPassword(strong, confirm: strong)
        #expect(await model.addEntry(plain("Bad", secret: "not base32 !!")) == "Secret key is not valid Base32")
        #expect(model.entries.isEmpty)
    }

    @Test func addNormalisesTheSecretAndKeepsInsertionOrder() async {
        let model = await started()
        _ = await model.setupPassword(strong, confirm: strong)
        _ = await model.addEntry(plain("B", secret: "jbsw y3dp ehpk 3pxp"))
        _ = await model.addEntry(plain("A"))
        #expect(model.entries.map(\.issuer) == ["B", "A"])
        #expect(model.entries[0].secret == "JBSWY3DPEHPK3PXP")
    }

    @Test func deleteRemovesTheEntryAndItSurvivesNoRelaunch() async {
        let model = await started()
        _ = await model.setupPassword(strong, confirm: strong)
        _ = await model.addEntry(plain("A"))
        _ = await model.addEntry(plain("B"))
        await model.deleteEntry(id: model.entries[0].id)
        #expect(model.entries.map(\.issuer) == ["B"])

        let relaunch = await started()
        _ = await relaunch.unlock(password: strong)
        #expect(relaunch.entries.map(\.issuer) == ["B"])
    }

    // MARK: Editing

    @Test func editPersistsAndKeepsSecretAndIcon() async {
        let model = await started()
        _ = await model.setupPassword(strong, confirm: strong)
        _ = await model.addEntry(VaultEntryPlaintext(issuer: "GitHub", accountName: "octocat",
                                                     secret: "JBSWY3DPEHPK3PXP", algorithm: "SHA256",
                                                     digits: 8, period: 60, icon: "🔑"))
        let original = model.entries[0]
        #expect(await model.updateEntry(original, issuer: "  GitHub Enterprise ", accountName: " work ", icon: original.icon) == nil)

        for candidate in [model.entries[0], await relaunchedFirstEntry()] {
            #expect(candidate.id == original.id)
            #expect(candidate.issuer == "GitHub Enterprise")
            #expect(candidate.accountName == "work")
            #expect(candidate.secret == "JBSWY3DPEHPK3PXP")
            #expect(candidate.algorithm == "SHA256" && candidate.digits == 8 && candidate.period == 60)
            #expect(candidate.icon == "🔑")
        }
    }

    private func relaunchedFirstEntry() async -> VaultEntry {
        let relaunch = await started()
        _ = await relaunch.unlock(password: strong)
        return relaunch.entries[0]
    }

    @Test func blankIssuerBecomesUnknownAndBlankAccountIsAllowed() async {
        let model = await started()
        _ = await model.setupPassword(strong, confirm: strong)
        _ = await model.addEntry(plain("GitHub"))
        _ = await model.updateEntry(model.entries[0], issuer: "   ", accountName: "", icon: model.entries[0].icon)
        #expect(model.entries[0].issuer == "Unknown")
        #expect(model.entries[0].accountName == "")
    }

    @Test func editingWhileLockedIsRefused() async {
        let model = await started()
        _ = await model.setupPassword(strong, confirm: strong)
        _ = await model.addEntry(plain("GitHub"))
        let entry = model.entries[0]
        model.lock()
        #expect(await model.updateEntry(entry, issuer: "Other", accountName: "x", icon: entry.icon) == "Vault is locked")
    }

    @Test func renamingReSortsAnAlphabeticalList() async {
        let model = await started()
        _ = await model.setupPassword(strong, confirm: strong)
        for name in ["Zeta", "alpha"] { _ = await model.addEntry(plain(name)) }
        model.setSortMode(.alphabetical)
        #expect(model.displayEntries().map(\.issuer) == ["alpha", "Zeta"])
        let zeta = model.entries.first { $0.issuer == "Zeta" }!
        _ = await model.updateEntry(zeta, issuer: "Aardvark", accountName: zeta.accountName, icon: zeta.icon)
        #expect(model.displayEntries().map(\.issuer) == ["Aardvark", "alpha"])
    }

    @Test func lookupFindsEntriesById() async {
        let model = await started()
        _ = await model.setupPassword(strong, confirm: strong)
        _ = await model.addEntry(plain("GitHub"))
        let id = model.entries[0].id
        #expect(model.entry(id: id)?.issuer == "GitHub")
        #expect(model.entry(id: "nope") == nil)
    }

    // MARK: Reordering

    private func issuers(_ model: AppModel) -> [String] { model.entries.map(\.issuer) }

    private func manualModel(_ names: [String]) async -> AppModel {
        let model = await started()
        _ = await model.setupPassword(strong, confirm: strong)
        for name in names { _ = await model.addEntry(plain(name)) }
        return model
    }

    @Test func movingPersistsTheNewOrderAndRenumbersSortOrder() async {
        let model = await manualModel(["A", "B", "C"])
        let shown = model.displayEntries().map(\.id)
        model.moveEntries(shownIds: shown, fromOffsets: [0], toOffset: 3)        // A to the end
        #expect(issuers(model) == ["B", "C", "A"])
        #expect(model.entries.map(\.sortOrder) == [0, 1, 2])
        await model.waitForPendingWrites()

        let relaunch = await started()
        _ = await relaunch.unlock(password: strong)
        #expect(issuers(relaunch) == ["B", "C", "A"])
        #expect(relaunch.entries.map(\.sortOrder) == [0, 1, 2])
    }

    @Test func movingWhileSearchingKeepsHiddenEntriesInPlace() async {
        let model = await manualModel(["red", "green", "blue", "grey"])
        let shown = model.displayEntries(query: "gre").map(\.id)               // green, grey
        #expect(shown.count == 2)
        model.moveEntries(shownIds: shown, fromOffsets: [1], toOffset: 0)        // grey above green
        #expect(issuers(model) == ["red", "grey", "blue", "green"])              // red and blue did not move
        await model.waitForPendingWrites()

        let relaunch = await started()
        _ = await relaunch.unlock(password: strong)
        #expect(issuers(relaunch) == ["red", "grey", "blue", "green"])
    }

    @Test func reorderingIsIgnoredOutsideManualSort() async {
        let model = await manualModel(["B", "A"])
        model.setSortMode(.alphabetical)
        model.moveEntries(shownIds: model.displayEntries().map(\.id), fromOffsets: [0], toOffset: 2)
        #expect(issuers(model) == ["B", "A"])                                    // stored (manual) order untouched
    }

    @Test func aMoveThatChangesNothingWritesNothingAndKeepsTheList() async {
        let model = await manualModel(["A", "B", "C"])
        let shown = model.displayEntries().map(\.id)
        model.moveEntries(shownIds: shown, fromOffsets: [1], toOffset: 1)
        model.moveEntries(shownIds: shown, fromOffsets: [1], toOffset: 2)
        #expect(issuers(model) == ["A", "B", "C"])
    }

    @Test func quickSuccessiveMovesLandInTheOrderTheyWereMade() async {
        let model = await manualModel(["A", "B", "C", "D"])
        for _ in 0..<3 {   // A to the end, three times over: A,B,C,D → B,C,D,A → C,D,A,B → D,A,B,C
            model.moveEntries(shownIds: model.displayEntries().map(\.id), fromOffsets: [0], toOffset: 4)
        }
        #expect(issuers(model) == ["D", "A", "B", "C"])
        await model.waitForPendingWrites()
        let relaunch = await started()
        _ = await relaunch.unlock(password: strong)
        #expect(issuers(relaunch) == ["D", "A", "B", "C"])
    }

    @Test func newEntriesAreAppendedAfterAReorder() async {
        let model = await manualModel(["A", "B"])
        model.moveEntries(shownIds: model.displayEntries().map(\.id), fromOffsets: [1], toOffset: 0)   // B, A
        await model.waitForPendingWrites()
        _ = await model.addEntry(plain("C"))
        #expect(issuers(model) == ["B", "A", "C"])
        let relaunch = await started()
        _ = await relaunch.unlock(password: strong)
        #expect(issuers(relaunch) == ["B", "A", "C"])
    }

    // MARK: Listing

    @Test func searchAndSortApplyToTheDisplayList() async {
        let model = await started()
        _ = await model.setupPassword(strong, confirm: strong)
        for name in ["Zeta", "alpha", "Mid"] { _ = await model.addEntry(plain(name)) }

        #expect(model.displayEntries().map(\.issuer) == ["Zeta", "alpha", "Mid"])      // manual
        model.setSortMode(.alphabetical)
        #expect(model.displayEntries().map(\.issuer) == ["alpha", "Mid", "Zeta"])
        model.setSortReversed(true)
        #expect(model.displayEntries().map(\.issuer) == ["Zeta", "Mid", "alpha"])
        #expect(model.displayEntries(query: "id").map(\.issuer) == ["Mid"])
    }

    @Test func copyingDoesNotReorderTheListUntilTheNextResort() async {
        let model = await started()
        _ = await model.setupPassword(strong, confirm: strong)
        for name in ["A", "B", "C"] { _ = await model.addEntry(plain(name)) }
        model.setSortMode(.mfu)
        #expect(model.displayEntries().map(\.issuer) == ["A", "B", "C"])

        let c = model.entries[2]
        await model.recordUse(of: c)
        #expect(model.displayEntries().map(\.issuer) == ["A", "B", "C"])     // stable mid-session
        model.setSortMode(.lru)                                              // explicit re-sort picks it up
        #expect(model.displayEntries().first?.issuer == "C")
    }

    // MARK: Settings & lifecycle

    @Test func settingsPersistAcrossLaunches() async {
        let model = await started()
        _ = await model.setupPassword(strong, confirm: strong)
        model.setSortMode(.mfu)
        model.setSortReversed(true)
        model.setLockTimeout(.oneHour)
        await model.waitForPendingWrites()

        let relaunch = await started()
        #expect(relaunch.sortMode == .mfu)
        #expect(relaunch.sortReversed)
        #expect(relaunch.lockTimeout == .oneHour)
    }

    @Test func layoutDefaultsToListAndPersistsAcrossLaunches() async {
        let model = await started()
        #expect(model.layoutMode == .list)
        _ = await model.setupPassword(strong, confirm: strong)
        model.setLayoutMode(.grid)
        #expect(model.layoutMode == .grid)
        await model.waitForPendingWrites()

        let relaunch = await started()
        #expect(relaunch.layoutMode == .grid)
        relaunch.setLayoutMode(.list)
        await relaunch.waitForPendingWrites()
        #expect(await started().layoutMode == .list)
    }

    @Test func layoutDoesNotAffectSortingOrSearch() async {
        let model = await started()
        _ = await model.setupPassword(strong, confirm: strong)
        for name in ["Zeta", "alpha"] { _ = await model.addEntry(plain(name)) }
        model.setSortMode(.alphabetical)
        let list = model.displayEntries().map(\.issuer)
        model.setLayoutMode(.grid)
        #expect(model.displayEntries().map(\.issuer) == list)
    }

    @Test func autoLockHonoursTheTimeout() async {
        let model = await started()
        _ = await model.setupPassword(strong, confirm: strong)
        model.setLockTimeout(.oneMinute)
        let t0 = Date(timeIntervalSince1970: 1_000_000)

        model.scenePhaseChanged(.background, now: t0)
        model.scenePhaseChanged(.active, now: t0.addingTimeInterval(30))
        #expect(model.phase == .unlocked)

        model.scenePhaseChanged(.background, now: t0)
        model.scenePhaseChanged(.active, now: t0.addingTimeInterval(61))
        #expect(model.phase == .locked)
    }

    @Test func inactiveAloneNeverLocks() async {
        // .inactive fires for Control Center, system alerts, the app switcher gesture…
        let model = await started()
        _ = await model.setupPassword(strong, confirm: strong)
        model.setLockTimeout(.oneMinute)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        model.scenePhaseChanged(.inactive, now: t0)
        model.scenePhaseChanged(.active, now: t0.addingTimeInterval(3_600))
        #expect(model.phase == .unlocked)
    }

    @Test func neverTimeoutNeverLocks() async {
        let model = await started()
        _ = await model.setupPassword(strong, confirm: strong)
        model.setLockTimeout(.never)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        model.scenePhaseChanged(.background, now: t0)
        model.scenePhaseChanged(.active, now: t0.addingTimeInterval(86_400 * 30))
        #expect(model.phase == .unlocked)
    }

    // MARK: Import & export

    private func unlocked(with issuers: [String] = []) async -> AppModel {
        let model = await started()
        _ = await model.setupPassword(strong, confirm: strong)
        for issuer in issuers { _ = await model.addEntry(plain(issuer)) }
        return model
    }

    @Test func plainExportImportsBackAsDuplicatesThatCanBeOverwrittenOrCopied() async throws {
        let model = await unlocked(with: ["GitHub", "Slack"])
        guard case .file(let file) = await model.exportVault(format: .plain, password: "") else {
            Issue.record("export failed"); return
        }

        guard case .ready(var candidates) = await model.prepareImport(file) else {
            Issue.record("import not ready"); return
        }
        #expect(candidates.count == 2 && candidates.allSatisfy(\.isDuplicate))
        #expect(candidates.map(\.action) == [.overwrite, .overwrite])

        candidates[1].action = .addCopy
        #expect(await model.confirmImport(candidates) == nil)
        #expect(model.entries.map(\.issuer) == ["GitHub", "Slack", "Slack"])
        #expect(model.entries.map(\.accountName) == ["me", "me", "me (2)"])
        #expect(model.toast == "Imported 2 entries")
    }

    @Test func encryptedExportNeedsItsPasswordToImport() async throws {
        let model = await unlocked(with: ["GitHub"])
        guard case .failed(let message) = await model.exportVault(format: .encrypted, password: "") else {
            Issue.record("exported without a password"); return
        }
        #expect(message == "Password required")
        guard case .file(let file) = await model.exportVault(format: .encrypted, password: "pw") else {
            Issue.record("export failed"); return
        }

        guard case .needsPassword = await model.prepareImport(file) else { Issue.record("no password asked"); return }
        guard case .failed(let wrong) = await model.prepareImport(file, password: "nope") else {
            Issue.record("wrong password accepted"); return
        }
        #expect(wrong == "Wrong password, or the file is damaged")
        guard case .ready(let candidates) = await model.prepareImport(file, password: "pw") else {
            Issue.record("right password rejected"); return
        }
        #expect(candidates.map(\.imported.issuer) == ["GitHub"])
    }

    @Test func unreadableFilesAndInvalidAccountsFailWithAMessage() async {
        let model = await unlocked()
        guard case .failed(let unknown) = await model.prepareImport("hello") else { Issue.record(); return }
        #expect(unknown == "Unrecognized file format")
        guard case .failed(let badUri) = await model.prepareImport("otpauth://totp/Bad?secret=JBSWY3DPEHPK3PXP&digits=2")
        else { Issue.record(); return }
        #expect(badUri == "Invalid otpauth URI: Digits must be between 4 and 10")
        guard case .failed(let invalid) = await model.prepareImport("otpauth://totp/Bad?secret=1111") else {
            Issue.record(); return
        }
        #expect(invalid == "Invalid account \"Bad\": Secret key is not valid Base32")
        #expect(model.entries.isEmpty)
    }

    @Test func importedEntriesAreAppendedAndKeptAcrossRelaunch() async throws {
        let model = await unlocked(with: ["GitHub"])
        guard case .ready(let candidates) = await model.prepareImport(
            "otpauth://totp/AWS:root?secret=JBSWY3DPEHPK3PXP\notpauth://totp/Okta:me?secret=JBSWY3DPEHPK3PXP")
        else { Issue.record(); return }
        #expect(await model.confirmImport(candidates) == nil)

        let relaunch = await started()
        #expect(await relaunch.unlock(password: strong))
        #expect(relaunch.entries.map(\.issuer) == ["GitHub", "AWS", "Okta"])
    }

    @Test func importIsRefusedWhileLocked() async {
        let model = await unlocked()
        guard case .ready(let candidates) = await model.prepareImport("otpauth://totp/AWS:root?secret=JBSWY3DPEHPK3PXP")
        else { Issue.record(); return }
        model.lock()
        #expect(await model.confirmImport(candidates) == "Vault is locked")
    }

    // MARK: Icons

    /// A 1×1 PNG: normalised to 64×64 like any picked image.
    private static let onePixelPng = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!

    private func normalisedPng() -> String {
        IconNormalizer.normalizedDataUrl(imageBytes: Self.onePixelPng)!
    }

    @Test func editChangesAndClearsTheIcon() async {
        let model = await unlocked(with: ["GitHub"])
        let entry = model.entries[0]
        #expect(await model.updateEntry(entry, issuer: "GitHub", accountName: "me", icon: "🔑") == nil)
        #expect(await relaunchedFirstEntry().icon == "🔑")
        #expect(await model.updateEntry(model.entries[0], issuer: "GitHub", accountName: "me", icon: nil) == nil)
        #expect(await relaunchedFirstEntry().icon == nil)
    }

    @Test func libraryIconsAreSavedDedupedRenamedDeletedAndSurviveRelaunch() async {
        let model = await unlocked()
        let png = normalisedPng()
        #expect(await model.addLibraryIcon(label: "Acme", dataUrl: png, source: Self.onePixelPng) == nil)
        #expect(await model.addLibraryIcon(label: "Again", dataUrl: png, source: Self.onePixelPng) == nil)
        #expect(model.libraryIcons.map(\.label) == ["Acme"])      // same content: the existing icon is kept

        let id = model.libraryIcons[0].id
        #expect(id == id.lowercased())
        #expect(await model.renameLibraryIcon(id: id, label: "  Acme Corp ") == nil)
        #expect(model.libraryIcons[0].label == "Acme Corp")
        #expect(await model.renameLibraryIcon(id: id, label: "   ") == nil)
        #expect(model.libraryIcons[0].label == "Icon")
        _ = await model.renameLibraryIcon(id: id, label: "Acme")

        let relaunch = await started()
        #expect(await relaunch.unlock(password: strong))
        #expect(relaunch.libraryIcons.map(\.label) == ["Acme"])

        #expect(await relaunch.removeLibraryIcon(id: id) == nil)
        #expect(relaunch.libraryIcons.isEmpty)
        let again = await started()
        _ = await again.unlock(password: strong)
        #expect(again.libraryIcons.isEmpty)
    }

    @Test func libraryIsClearedOnLockAndRefusedWhileLocked() async {
        let model = await unlocked()
        _ = await model.addLibraryIcon(label: "Acme", dataUrl: normalisedPng(), source: nil)
        model.lock()
        #expect(model.libraryIcons.isEmpty)
        #expect(await model.addLibraryIcon(label: "X", dataUrl: "data:image/png;base64,AA", source: nil) == "Vault is locked")
        #expect(await model.removeLibraryIcon(id: "x") == "Vault is locked")
    }

    @Test func aFullLibraryExplainsItself() async {
        let model = await unlocked()
        for n in 0..<IconLibraryLimits.maxIcons {
            #expect(await model.addLibraryIcon(label: "I\(n)", dataUrl: "data:image/png;base64,AAAA\(n)", source: nil) == nil)
        }
        #expect(await model.addLibraryIcon(label: "Extra", dataUrl: "data:image/png;base64,ZZZZ", source: nil)
                == "Icon library is full (100 max). Delete some icons first.")
    }

    private func iconExport(_ png: String) async -> String {
        let model = await unlocked()
        _ = await model.addEntry(VaultEntryPlaintext(issuer: "Acme", accountName: "me", secret: "JBSWY3DPEHPK3PXP", icon: png))
        _ = await model.addEntry(VaultEntryPlaintext(issuer: "Acme2", accountName: "me", secret: "JBSWY3DPEHPK3PXP", icon: png))
        guard case .file(let file) = await model.exportVault(format: .plain, password: "") else { return "" }
        return file
    }

    @Test func importAddsEmbeddedIconsToTheLibraryOnceWhenAsked() async throws {
        let file = await iconExport(normalisedPng())
        let fresh = try AppDatabase.inMemory()
        let model = AppModel(repository: VaultRepository(db: fresh), iconLibrary: IconLibraryRepository(db: fresh),
                             biometrics: FakeBiometrics())
        await model.start()
        _ = await model.setupPassword(strong, confirm: strong)
        guard case .ready(let candidates) = await model.prepareImport(file) else { Issue.record(); return }
        #expect(model.addIconsToLibrary)        // on by default, as on Android
        #expect(await model.confirmImport(candidates) == nil)
        #expect(model.libraryIcons.map(\.label) == ["Acme"])
        #expect(model.libraryIcons[0].sourceHash != nil)
        #expect(model.toast == "Imported 2 entries · 1 icon added")
    }

    @Test func importLeavesTheLibraryAloneWhenTheOptionIsOff() async throws {
        let file = await iconExport(normalisedPng())
        let fresh = try AppDatabase.inMemory()
        let model = AppModel(repository: VaultRepository(db: fresh), iconLibrary: IconLibraryRepository(db: fresh),
                             biometrics: FakeBiometrics())
        await model.start()
        _ = await model.setupPassword(strong, confirm: strong)
        guard case .ready(let candidates) = await model.prepareImport(file) else { Issue.record(); return }
        model.addIconsToLibrary = false
        #expect(await model.confirmImport(candidates) == nil)
        #expect(model.libraryIcons.isEmpty)
        #expect(model.entries.allSatisfy { $0.icon != nil })
        #expect(model.toast == "Imported 2 entries")
    }

    // MARK: Upcoming code

    @Test func showNextCodeDefaultsOffAndPersists() async {
        let model = await started()
        #expect(model.showNextCode == false)
        model.setShowNextCode(true)
        await model.waitForPendingWrites()
        #expect(await started().showNextCode)
    }

    @Test func copyHandsOutTheNextCodeOnlyInTheLastSecondsWhenEnabled() async throws {
        let model = await unlocked(with: ["GitHub"])
        let entry = try #require(model.entries.first)
        let lastSeconds = Date(timeIntervalSince1970: 59_999_998)     // 2 s left in the step
        let midStep = Date(timeIntervalSince1970: 59_999_980)         // 20 s left

        model.copyCode(of: entry, now: lastSeconds)
        #expect(model.toast?.hasPrefix("Code copied") == true)

        model.setShowNextCode(true)
        model.copyCode(of: entry, now: midStep)
        #expect(model.toast?.hasPrefix("Code copied") == true)
        model.copyCode(of: entry, now: lastSeconds)
        #expect(model.toast?.hasPrefix("Next code copied") == true)
        #expect(UIPasteboard.general.string == entry.code(at: 60_000_000 + 2))   // the next step's code
    }

    // MARK: Biometric unlock

    @Test func biometricUnlockAfterEnablingSurvivesARelaunch() async throws {
        let model = await unlocked(with: ["GitHub"])
        #expect(model.biometry == .faceID && !model.canUnlockWithBiometrics)
        #expect(await model.setBiometricEnabled(true) == nil)
        #expect(model.biometricEnabled && biometrics.prompts == 1)

        let relaunch = await started()
        #expect(relaunch.phase == .locked && relaunch.canUnlockWithBiometrics)
        #expect(await relaunch.unlockWithBiometrics())
        #expect(relaunch.phase == .unlocked)
        #expect(relaunch.entries.map(\.issuer) == ["GitHub"])
    }

    @Test func cancellingThePromptChangesNothing() async {
        let model = await unlocked()
        biometrics.nextPrompt = .failure(.cancelled)
        #expect(await model.setBiometricEnabled(true) == nil)
        #expect(!model.biometricEnabled && biometrics.storedKey == nil)

        #expect(await model.setBiometricEnabled(true) == nil)
        model.lock()
        biometrics.nextPrompt = .failure(.cancelled)
        #expect(await model.unlockWithBiometrics() == false)
        #expect(model.phase == .locked && model.errorMessage == nil && model.biometricEnabled)
    }

    @Test func aFailedPromptIsReported() async {
        let model = await unlocked()
        biometrics.nextPrompt = .failure(.failed("Too many attempts"))
        #expect(await model.setBiometricEnabled(true) == "Failed to enable biometric unlock: Too many attempts")
        #expect(!model.biometricEnabled)
    }

    @Test func anInvalidatedKeyTurnsBiometricUnlockOff() async {
        let model = await unlocked()
        _ = await model.setBiometricEnabled(true)
        model.lock()
        biometrics.storedKey = nil          // enrollment changed: the Keychain item is unreadable
        biometrics.reportsStoredKey = true  // …but still "there" without a prompt
        #expect(await model.unlockWithBiometrics() == false)
        #expect(!model.biometricEnabled && !model.canUnlockWithBiometrics)
        #expect(model.errorMessage?.hasPrefix("Biometric unlock was turned off") == true)

        let relaunch = await started()
        #expect(!relaunch.canUnlockWithBiometrics)
    }

    @Test func turningOffRemovesTheKey() async {
        let model = await unlocked()
        _ = await model.setBiometricEnabled(true)
        #expect(await model.setBiometricEnabled(false) == nil)
        #expect(biometrics.storedKey == nil && !model.biometricEnabled)
        #expect(await started().canUnlockWithBiometrics == false)
    }

    @Test func noSensorMeansNoBiometricUnlockEvenIfTurnedOnEarlier() async {
        let model = await unlocked()
        _ = await model.setBiometricEnabled(true)
        biometrics.biometry = nil
        let relaunch = await started()
        #expect(relaunch.biometricEnabled && !relaunch.canUnlockWithBiometrics)
        #expect(await relaunch.unlockWithBiometrics() == false)
    }

    @Test func aFreshInstallDropsAKeyLeftByAnEarlierOne() async {
        biometrics.storedKey = Data(repeating: 7, count: 32)
        _ = await started()                 // not set up
        #expect(biometrics.storedKey == nil)
    }
}

/// In-memory stand-in for the Keychain + LocalAuthentication store.
final class FakeBiometrics: BiometricKeyStore, @unchecked Sendable {
    var biometry: BiometryKind? = .faceID
    var storedKey: Data?
    /// Overrides `storedKey != nil` for `hasStoredKey` (an invalidated item still exists).
    var reportsStoredKey: Bool?
    /// The outcome of the next prompt; success by default.
    var nextPrompt: Result<Void, BiometricError> = .success(())
    private(set) var prompts = 0

    func availableBiometry() -> BiometryKind? { biometry }
    func hasStoredKey() -> Bool { reportsStoredKey ?? (storedKey != nil) }

    func enroll(vaultKey: Data, reason: String) async throws {
        try prompt()
        storedKey = vaultKey
    }

    func loadVaultKey(reason: String) async throws -> Data? {
        guard hasStoredKey() else { return nil }
        try prompt()
        return storedKey
    }

    func removeKey() {
        storedKey = nil
        reportsStoredKey = nil
    }

    private func prompt() throws {
        prompts += 1
        defer { nextPrompt = .success(()) }
        try nextPrompt.get()
    }
}
