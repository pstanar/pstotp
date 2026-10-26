import Foundation
import PsTotpCore
import SwiftUI
import Testing
@testable import PsTotp

@MainActor
@Suite("AppModel")
struct AppModelTests {
    let db: AppDatabase

    init() throws { db = try AppDatabase.inMemory() }

    private func makeModel() -> AppModel { AppModel(repository: VaultRepository(db: db)) }

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
}
