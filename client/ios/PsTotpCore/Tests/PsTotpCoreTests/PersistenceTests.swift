import Foundation
import GRDB
import Testing
@testable import PsTotpCore

@Suite("Persistence")
struct PersistenceTests {

    private func record(_ id: String, sort: Int = 0, deleted: Int64? = nil) -> VaultEntryRecord {
        VaultEntryRecord(id: id, encryptedPayload: Data([1, 2, 3]), sortOrder: sort,
                         createdAt: 1_000, updatedAt: 1_000, deletedAt: deleted)
    }

    // MARK: Schema

    @Test func schemaMatchesRoomVersion3() async throws {
        let db = try AppDatabase.inMemory()
        let columns: [String: [String]] = try await db.writer.read { db in
            var out = [String: [String]]()
            for table in ["vault_entries", "settings", "entry_usage"] {
                out[table] = try db.columns(in: table).map(\.name)
            }
            return out
        }
        #expect(columns["vault_entries"] == ["id", "encryptedPayload", "sortOrder", "createdAt", "updatedAt",
                                             "deletedAt", "pendingSync", "entryVersion", "serverUpdatedAt"])
        #expect(columns["settings"] == ["key", "value"])
        #expect(columns["entry_usage"] == ["entryId", "lastUsedAt", "useCount"])
    }

    @Test func fileDatabasePersistsAndReopens() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("nested/pstotp.db")   // parent directories are created

        do {
            let repo = VaultRepository(db: try AppDatabase.open(at: url))
            try await repo.setSetting("greeting", "hello")
        }
        // Reopening re-runs the migrator, which must be a no-op on an up-to-date file.
        let reopened = VaultRepository(db: try AppDatabase.open(at: url))
        #expect(try await reopened.getSetting("greeting") == "hello")
    }

    // MARK: Vault entries

    @Test func liveQueryOrdersBySortOrderAndHidesSoftDeleted() async throws {
        let db = try AppDatabase.inMemory()
        try await db.writer.write { db in
            try VaultEntryQueries.upsert(db, record("c", sort: 2))
            try VaultEntryQueries.upsert(db, record("a", sort: 0))
            try VaultEntryQueries.upsert(db, record("b", sort: 1))
            try VaultEntryQueries.upsert(db, record("gone", sort: 3, deleted: 5))
        }
        let live = try await db.writer.read { try VaultEntryQueries.live($0).map(\.id) }
        #expect(live == ["a", "b", "c"])
        // …but a deleted row is still addressable by id (needed to sync the deletion).
        #expect(try await db.writer.read { try VaultEntryQueries.byId($0, "gone") }?.deletedAt == 5)
    }

    @Test func maxSortOrderIgnoresDeletedAndIsNilWhenEmpty() async throws {
        let db = try AppDatabase.inMemory()
        #expect(try await db.writer.read { try VaultEntryQueries.maxSortOrder($0) } == nil)
        try await db.writer.write { db in
            try VaultEntryQueries.upsert(db, record("a", sort: 4))
            try VaultEntryQueries.upsert(db, record("z", sort: 9, deleted: 1))
        }
        #expect(try await db.writer.read { try VaultEntryQueries.maxSortOrder($0) } == 4)
    }

    @Test func upsertReplacesExistingRow() async throws {
        let db = try AppDatabase.inMemory()
        try await db.writer.write { db in
            try VaultEntryQueries.upsert(db, record("a", sort: 1))
            var changed = record("a", sort: 7)
            changed.encryptedPayload = Data([9])
            try VaultEntryQueries.upsert(db, changed)
        }
        let rows = try await db.writer.read { try VaultEntryRecord.fetchAll($0) }
        #expect(rows.count == 1)
        #expect(rows[0].sortOrder == 7)
        #expect(rows[0].encryptedPayload == Data([9]))
    }

    @Test func recordRoundTripsAllColumns() async throws {
        let db = try AppDatabase.inMemory()
        let full = VaultEntryRecord(
            id: "x", encryptedPayload: Data((0...255).map { UInt8($0) }), sortOrder: -3,
            createdAt: 1_700_000_000_123, updatedAt: 1_700_000_000_456, deletedAt: 1_700_000_000_789,
            pendingSync: true, entryVersion: 12, serverUpdatedAt: "2026-10-25T16:00:00Z")
        try await db.writer.write { try VaultEntryQueries.upsert($0, full) }
        #expect(try await db.writer.read { try VaultEntryQueries.byId($0, "x") } == full)
    }

    // MARK: Settings

    @Test func settingsGetSetDeleteAndIsSetUp() async throws {
        let db = try AppDatabase.inMemory()
        #expect(try await db.writer.read { try SettingsQueries.get($0, "k") } == nil)
        #expect(try await db.writer.read { try SettingsQueries.isSetUp($0) } == false)

        try await db.writer.write { db in
            try SettingsQueries.set(db, "k", "v1")
            try SettingsQueries.set(db, "k", "v2")                          // replace
            try SettingsQueries.set(db, SettingsKeys.passwordVerifier, "x")
        }
        #expect(try await db.writer.read { try SettingsQueries.get($0, "k") } == "v2")
        #expect(try await db.writer.read { try SettingsQueries.isSetUp($0) })

        try await db.writer.write { try SettingsQueries.delete($0, "k") }
        #expect(try await db.writer.read { try SettingsQueries.get($0, "k") } == nil)
    }

    @Test func settingsKeysMatchAndroid() {
        #expect(SettingsKeys.kdfSalt == "kdf_salt")
        #expect(SettingsKeys.passwordVerifier == "password_verifier")
        #expect(SettingsKeys.encryptedVaultKey == "encrypted_vault_key")
        #expect(SettingsKeys.lockTimeoutMs == "lock_timeout_ms")
        #expect(SettingsKeys.pendingReorder == "pending_reorder")
        #expect(SettingsKeys.defaultLockTimeoutMs == 300_000)
    }

    // MARK: Usage

    @Test func recordUseInsertsThenIncrements() async throws {
        let db = try AppDatabase.inMemory()
        try await db.writer.write { try EntryUsageQueries.recordUse($0, entryId: "a", now: 100) }
        try await db.writer.write { try EntryUsageQueries.recordUse($0, entryId: "a", now: 250) }
        try await db.writer.write { try EntryUsageQueries.recordUse($0, entryId: "b", now: 300) }
        let all = try await db.writer.read { try EntryUsageQueries.all($0) }.sorted { $0.entryId < $1.entryId }
        #expect(all == [EntryUsageRecord(entryId: "a", lastUsedAt: 250, useCount: 2),
                        EntryUsageRecord(entryId: "b", lastUsedAt: 300, useCount: 1)])
    }
}
