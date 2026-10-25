import Foundation
import GRDB
import Testing
@testable import PsTotpCore

/// Settable clock so timestamps are deterministic.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64
    init(_ start: Int64 = 1_000) { value = start }
    func set(_ v: Int64) { lock.withLock { value = v } }
    var now: Int64 { lock.withLock { value } }
}

@Suite("VaultRepository")
struct VaultRepositoryTests {
    let db: AppDatabase
    let repo: VaultRepository
    let clock = TestClock()
    let key = KeyDerivation.generateVaultKey()

    init() throws {
        db = try AppDatabase.inMemory()
        let clock = clock
        repo = VaultRepository(db: db, now: { clock.now })
    }

    private func plain(_ issuer: String, _ account: String = "me") -> VaultEntryPlaintext {
        VaultEntryPlaintext(issuer: issuer, accountName: account, secret: "JBSWY3DPEHPK3PXP")
    }

    private func rawRecord(_ id: String) async throws -> VaultEntryRecord? {
        try await db.writer.read { try VaultEntryQueries.byId($0, id) }
    }

    // MARK: Setup & unlock

    @Test func setupThenUnlock() async throws {
        #expect(try await repo.isSetUp() == false)
        #expect(try await repo.unlockVault(password: "anything") == nil)   // not set up yet

        let vaultKey = try await repo.setupPassword("correct horse")
        #expect(vaultKey.count == 32)
        #expect(try await repo.isSetUp())
        #expect(try await repo.getSetting(SettingsKeys.mode) == SettingsKeys.modeStandalone)
        #expect(try await repo.isConnected() == false)

        #expect(try await repo.unlockVault(password: "correct horse") == vaultKey)
        #expect(try await repo.unlockVault(password: "wrong") == nil)
    }

    @Test func setupPersistsAllFourSettings() async throws {
        _ = try await repo.setupPassword("pw-pw-pw-pw")
        for key in [SettingsKeys.kdfSalt, SettingsKeys.passwordVerifier, SettingsKeys.encryptedVaultKey, SettingsKeys.mode] {
            #expect(try await repo.getSetting(key) != nil, "missing \(key)")
        }
        #expect(Data(base64Encoded: try #require(try await repo.getSetting(SettingsKeys.kdfSalt)))?.count == 16)
    }

    @Test func corruptStoredSettingsThrowInsteadOfReportingWrongPassword() async throws {
        _ = try await repo.setupPassword("pw-pw-pw-pw")
        try await repo.setSetting(SettingsKeys.kdfSalt, "!!! not base64 !!!")
        await #expect(throws: RepositoryError.corruptSettings) {
            try await repo.unlockVault(password: "pw-pw-pw-pw")
        }
    }

    // MARK: CRUD

    @Test func addAssignsLowercaseUuidAndSequentialSortOrder() async throws {
        let a = try await repo.addEntry(vaultKey: key, plaintext: plain("A"))
        let b = try await repo.addEntry(vaultKey: key, plaintext: plain("B"))
        let c = try await repo.addEntry(vaultKey: key, plaintext: plain("C"))
        let orders: [Int] = [a.sortOrder, b.sortOrder, c.sortOrder]
        #expect(orders == [0, 1, 2])
        for id in [a.id, b.id, c.id] {
            #expect(id == id.lowercased())             // AAD + server GUID: must match Android/web casing
            #expect(UUID(uuidString: id) != nil)
        }
        #expect(Set([a.id, b.id, c.id]).count == 3)
    }

    @Test func addThenGetRoundTrips() async throws {
        let p = VaultEntryPlaintext(issuer: "Bank/Corp", accountName: "bob: work", secret: "NBSWY3DPFQQHO33SNRSCC",
                                    algorithm: "SHA512", digits: 8, period: 45, icon: "🏦")
        let added = try await repo.addEntry(vaultKey: key, plaintext: p)
        let all = try await repo.getAllEntries(vaultKey: key)
        #expect(all == [added])
        #expect(all[0].issuer == "Bank/Corp" && all[0].accountName == "bob: work")
        #expect(all[0].icon == "🏦" && all[0].digits == 8 && all[0].period == 45 && all[0].algorithm == "SHA512")
    }

    @Test func getAllEntriesOnEmptyVaultIsEmpty() async throws {
        #expect(try await repo.getAllEntries(vaultKey: key).isEmpty)
        // Even with a bogus key: nothing to decrypt, so nothing can mismatch.
        #expect(try await repo.getAllEntries(vaultKey: KeyDerivation.generateVaultKey()).isEmpty)
    }

    @Test func payloadIsEncryptedAndBoundToEntryId() async throws {
        let e = try await repo.addEntry(vaultKey: key, plaintext: plain("Secret Issuer"))
        let row = try #require(try await rawRecord(e.id))
        #expect(row.encryptedPayload.count > 12 + 16)
        #expect(row.encryptedPayload.range(of: Data("Secret Issuer".utf8)) == nil)   // not plaintext

        // Same bytes under another id must not decrypt (AAD = id).
        var moved = row
        moved.id = "someone-elses-id"
        #expect(throws: CryptoError.decryptionFailed) {
            try VaultRepository.decryptEntry(vaultKey: key, record: moved)
        }
    }

    @Test func updateReencryptsAndKeepsIdentityFields() async throws {
        clock.set(1_000)
        var e = try await repo.addEntry(vaultKey: key, plaintext: plain("Old"))
        clock.set(5_000)
        e.issuer = "New"
        e.accountName = "renamed"
        e.icon = "🔑"
        try await repo.updateEntry(vaultKey: key, entry: e)

        let all = try await repo.getAllEntries(vaultKey: key)
        #expect(all.count == 1)
        #expect(all[0].issuer == "New" && all[0].accountName == "renamed" && all[0].icon == "🔑")
        let row = try #require(try await rawRecord(e.id))
        #expect(row.createdAt == 1_000 && row.updatedAt == 5_000)
        #expect(row.sortOrder == e.sortOrder)
    }

    @Test func updateOfUnknownEntryIsANoOp() async throws {
        let ghost = VaultEntry(id: "nope", issuer: "X", accountName: "Y", secret: "JBSW")
        try await repo.updateEntry(vaultKey: key, entry: ghost)
        #expect(try await rawRecord("nope") == nil)
    }

    @Test func deleteSoftDeletesAndDropsUsage() async throws {
        clock.set(1_000)
        let a = try await repo.addEntry(vaultKey: key, plaintext: plain("A"))
        let b = try await repo.addEntry(vaultKey: key, plaintext: plain("B"))
        try await repo.recordEntryUse(entryId: a.id)
        try await repo.recordEntryUse(entryId: b.id)

        clock.set(9_000)
        try await repo.deleteEntry(id: a.id)

        #expect(try await repo.getAllEntries(vaultKey: key).map(\.id) == [b.id])
        let row = try #require(try await rawRecord(a.id))          // retained so the delete can sync
        #expect(row.deletedAt == 9_000 && row.updatedAt == 9_000)
        #expect(try await repo.getAllUsage().map(\.entryId) == [b.id])
    }

    @Test func newEntryReusesSortSlotOfDeletedTail() async throws {
        // Same as Android: max sortOrder ignores deleted rows.
        _ = try await repo.addEntry(vaultKey: key, plaintext: plain("A"))
        _ = try await repo.addEntry(vaultKey: key, plaintext: plain("B"))
        let c = try await repo.addEntry(vaultKey: key, plaintext: plain("C"))
        try await repo.deleteEntry(id: c.id)
        let d = try await repo.addEntry(vaultKey: key, plaintext: plain("D"))
        #expect(d.sortOrder == 2)
    }

    @Test func reorderRewritesSortOrder() async throws {
        let a = try await repo.addEntry(vaultKey: key, plaintext: plain("A"))
        let b = try await repo.addEntry(vaultKey: key, plaintext: plain("B"))
        let c = try await repo.addEntry(vaultKey: key, plaintext: plain("C"))
        try await repo.reorderEntries(orderedIds: [c.id, a.id, b.id])
        let all = try await repo.getAllEntries(vaultKey: key)
        #expect(all.map(\.id) == [c.id, a.id, b.id])
        let orders: [Int] = all.map(\.sortOrder)
        #expect(orders == [0, 1, 2])
    }

    // MARK: Wrong keys / corruption

    @Test func wrongVaultKeyThrowsMismatchNotAnEmptyVault() async throws {
        _ = try await repo.addEntry(vaultKey: key, plaintext: plain("A"))
        _ = try await repo.addEntry(vaultKey: key, plaintext: plain("B"))
        let wrong = KeyDerivation.generateVaultKey()
        await #expect(throws: VaultKeyMismatchError(failed: 2, total: 2)) {
            try await repo.getAllEntries(vaultKey: wrong)
        }
    }

    @Test func singleEntryVaultWithWrongKeyIsAMismatch() async throws {
        _ = try await repo.addEntry(vaultKey: key, plaintext: plain("A"))
        await #expect(throws: VaultKeyMismatchError(failed: 1, total: 1)) {
            try await repo.getAllEntries(vaultKey: KeyDerivation.generateVaultKey())
        }
    }

    @Test func oneCorruptEntryIsToleratedTwoAreNot() async throws {
        let a = try await repo.addEntry(vaultKey: key, plaintext: plain("A"))
        let b = try await repo.addEntry(vaultKey: key, plaintext: plain("B"))
        let c = try await repo.addEntry(vaultKey: key, plaintext: plain("C"))

        func corrupt(_ id: String) async throws {
            try await db.writer.write { db in
                var row = try #require(try VaultEntryQueries.byId(db, id))
                row.encryptedPayload[row.encryptedPayload.count - 1] ^= 0xFF
                try VaultEntryQueries.upsert(db, row)
            }
        }
        try await corrupt(a.id)
        #expect(try await repo.getAllEntries(vaultKey: key).map(\.id) == [b.id, c.id])

        try await corrupt(b.id)
        await #expect(throws: VaultKeyMismatchError(failed: 2, total: 3)) {
            try await repo.getAllEntries(vaultKey: key)
        }
    }

    @Test func mismatchHeuristic() {
        #expect(!isVaultKeyMismatch(failures: 0, successes: 0))
        #expect(!isVaultKeyMismatch(failures: 0, successes: 100))
        #expect(!isVaultKeyMismatch(failures: 1, successes: 1))
        #expect(!isVaultKeyMismatch(failures: 1, successes: 99))
        #expect(isVaultKeyMismatch(failures: 1, successes: 0))
        #expect(isVaultKeyMismatch(failures: 2, successes: 8))
        #expect(isVaultKeyMismatch(failures: 100, successes: 0))
    }

    // MARK: Standalone vs connected bookkeeping

    @Test func standaloneModeNeverQueuesSync() async throws {
        let e = try await repo.addEntry(vaultKey: key, plaintext: plain("A"))
        try await repo.reorderEntries(orderedIds: [e.id])
        #expect(try await rawRecord(e.id)?.pendingSync == false)
        #expect(try await repo.isPendingReorder() == false)

        var edited = e
        edited.issuer = "B"
        try await repo.updateEntry(vaultKey: key, entry: edited)
        try await repo.deleteEntry(id: e.id)
        #expect(try await rawRecord(e.id)?.pendingSync == false)
    }

    @Test func connectedModeQueuesSyncForEveryMutation() async throws {
        try await repo.setSetting(SettingsKeys.mode, SettingsKeys.modeConnected)
        #expect(try await repo.isConnected())

        var e = try await repo.addEntry(vaultKey: key, plaintext: plain("A"))
        #expect(try await rawRecord(e.id)?.pendingSync == true)

        // Simulate a successful sync, then edit.
        try await db.writer.write { try $0.execute(sql: "UPDATE vault_entries SET pendingSync = 0") }
        e.issuer = "A2"
        try await repo.updateEntry(vaultKey: key, entry: e)
        #expect(try await rawRecord(e.id)?.pendingSync == true)

        try await db.writer.write { try $0.execute(sql: "UPDATE vault_entries SET pendingSync = 0") }
        try await repo.deleteEntry(id: e.id)
        #expect(try await rawRecord(e.id)?.pendingSync == true)

        try await repo.reorderEntries(orderedIds: [])
        #expect(try await repo.isPendingReorder())
        try await repo.clearPendingReorder()
        #expect(try await repo.isPendingReorder() == false)
    }

    @Test func payloadBase64AndVersionAccessors() async throws {
        let e = try await repo.addEntry(vaultKey: key, plaintext: plain("A"))
        let row = try #require(try await rawRecord(e.id))
        #expect(try await repo.getEntryPayloadBase64(entryId: e.id) == row.encryptedPayload.base64EncodedString())
        #expect(try await repo.getEntryPayloadBase64(entryId: "nope") == nil)
        #expect(try await repo.getEntryVersion(entryId: e.id) == 0)
        try await db.writer.write { try $0.execute(sql: "UPDATE vault_entries SET entryVersion = 7") }
        #expect(try await repo.getEntryVersion(entryId: e.id) == 7)
        #expect(try await repo.getEntryVersion(entryId: "nope") == 0)
    }

    @Test func usageIsRecordedWithTheInjectedClock() async throws {
        let e = try await repo.addEntry(vaultKey: key, plaintext: plain("A"))
        clock.set(111)
        try await repo.recordEntryUse(entryId: e.id)
        clock.set(222)
        try await repo.recordEntryUse(entryId: e.id)
        #expect(try await repo.getAllUsage() == [EntryUsageRecord(entryId: e.id, lastUsedAt: 222, useCount: 2)])
    }

    // MARK: Observation

    @Test func observationEmitsOnChanges() async throws {
        var updates = repo.observeRecords().makeAsyncIterator()
        #expect(try await updates.next() == [])

        let e = try await repo.addEntry(vaultKey: key, plaintext: plain("A"))
        let afterAdd = try #require(try await updates.next())
        #expect(afterAdd.map(\.id) == [e.id])
        #expect(try VaultRepository.decrypt(vaultKey: key, records: afterAdd).map(\.issuer) == ["A"])

        try await repo.deleteEntry(id: e.id)
        #expect(try await updates.next() == [])
    }

    // MARK: Interop

    @Test func decryptsPayloadWrittenByAndroidAndWebFormat() async throws {
        let fx = Vectors.shared.vaultEntry
        let payload = try #require(Data(base64Encoded: fx.payloadBase64))
        let record = VaultEntryRecord(id: fx.id, encryptedPayload: payload, sortOrder: 3, createdAt: 1, updatedAt: 1)
        try await db.writer.write { try VaultEntryQueries.upsert($0, record) }

        let entries = try await repo.getAllEntries(vaultKey: Data(hex: fx.vaultKeyHex))
        let p = fx.plaintext
        #expect(entries == [VaultEntry(id: fx.id, issuer: p.issuer, accountName: p.accountName, secret: p.secret,
                                       algorithm: p.algorithm, digits: p.digits, period: p.period,
                                       icon: p.icon, version: 1, sortOrder: 3)])
    }

    @Test func ourPayloadUsesTheSameJsonShapeAsOtherClients() throws {
        let json = try VaultRepository.plaintextToJson(
            VaultEntryPlaintext(issuer: "I", accountName: "A", secret: "S"))
        let obj = try #require(try JSONSerialization.jsonObject(with: json) as? JSONObject)
        #expect(Set(obj.keys) == ["issuer", "accountName", "secret", "algorithm", "digits", "period"])  // no icon key
    }

    @Test func emptyOrMissingIconDecryptsToNil() throws {
        func decode(_ json: String) throws -> VaultEntryPlaintext {
            try VaultRepository.jsonToPlaintext(Data(json.utf8))
        }
        #expect(try decode(#"{"issuer":"I","accountName":"A","secret":"S"}"#).icon == nil)
        #expect(try decode(#"{"issuer":"I","accountName":"A","secret":"S","icon":""}"#).icon == nil)
        #expect(try decode(#"{"issuer":"I","accountName":"A","secret":"S","icon":null}"#).icon == nil)
        let d = try decode(#"{"issuer":"I","accountName":"A","secret":"S"}"#)
        #expect(d.algorithm == "SHA1" && d.digits == 6 && d.period == 30)       // defaults
        #expect(throws: RepositoryError.malformedPayload) { try decode(#"{"issuer":"I"}"#) }
    }
}
