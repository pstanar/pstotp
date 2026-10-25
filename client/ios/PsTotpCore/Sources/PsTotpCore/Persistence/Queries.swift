import Foundation
import GRDB

// Synchronous query helpers (the Room DAOs). They take a `Database` so the repository can compose
// several of them inside one transaction.

enum VaultEntryQueries {
    /// Non-deleted entries ordered by sort order.
    static func live(_ db: Database) throws -> [VaultEntryRecord] {
        try VaultEntryRecord
            .filter(Column("deletedAt") == nil)
            .order(Column("sortOrder").asc)
            .fetchAll(db)
    }

    static func observeLive() -> ValueObservation<ValueReducers.Fetch<[VaultEntryRecord]>> {
        ValueObservation.tracking { try live($0) }
    }

    /// By id, including soft-deleted entries.
    static func byId(_ db: Database, _ id: String) throws -> VaultEntryRecord? {
        try VaultEntryRecord.fetchOne(db, key: id)
    }

    /// Insert or replace.
    static func upsert(_ db: Database, _ record: VaultEntryRecord) throws {
        try record.save(db)
    }

    static func softDelete(_ db: Database, id: String, timestamp: Int64) throws {
        try db.execute(
            sql: "UPDATE vault_entries SET deletedAt = ?, updatedAt = ? WHERE id = ?",
            arguments: [timestamp, timestamp, id])
    }

    /// Highest sort order among non-deleted entries (nil when there are none).
    static func maxSortOrder(_ db: Database) throws -> Int? {
        try Int.fetchOne(db, sql: "SELECT MAX(sortOrder) FROM vault_entries WHERE deletedAt IS NULL")
    }

    static func updateSortOrder(_ db: Database, id: String, sortOrder: Int) throws {
        try db.execute(
            sql: "UPDATE vault_entries SET sortOrder = ? WHERE id = ?", arguments: [sortOrder, id])
    }

    static func markPendingSync(_ db: Database, id: String) throws {
        try db.execute(sql: "UPDATE vault_entries SET pendingSync = 1 WHERE id = ?", arguments: [id])
    }
}

enum SettingsQueries {
    static func get(_ db: Database, _ key: String) throws -> String? {
        try String.fetchOne(db, sql: "SELECT value FROM settings WHERE key = ?", arguments: [key])
    }

    static func set(_ db: Database, _ key: String, _ value: String) throws {
        try SettingsRecord(key: key, value: value).save(db)
    }

    static func delete(_ db: Database, _ key: String) throws {
        try db.execute(sql: "DELETE FROM settings WHERE key = ?", arguments: [key])
    }

    /// The app is set up once a password verifier exists.
    static func isSetUp(_ db: Database) throws -> Bool {
        try get(db, SettingsKeys.passwordVerifier) != nil
    }
}

enum EntryUsageQueries {
    static func all(_ db: Database) throws -> [EntryUsageRecord] {
        try EntryUsageRecord.fetchAll(db)
    }

    static func recordUse(_ db: Database, entryId: String, now: Int64) throws {
        try db.execute(
            sql: """
                INSERT INTO entry_usage (entryId, lastUsedAt, useCount) VALUES (?, ?, 1)
                ON CONFLICT(entryId) DO UPDATE SET lastUsedAt = excluded.lastUsedAt, useCount = useCount + 1
                """,
            arguments: [entryId, now])
    }

    static func delete(_ db: Database, entryId: String) throws {
        try db.execute(sql: "DELETE FROM entry_usage WHERE entryId = ?", arguments: [entryId])
    }
}
