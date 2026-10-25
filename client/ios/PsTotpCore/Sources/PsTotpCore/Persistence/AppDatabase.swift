import Foundation
import GRDB

/// SQLite database for PsTotp (the GRDB counterpart of the Android Room `AppDatabase`).
///
/// Stores encrypted vault entries and app settings. The database file itself is NOT encrypted —
/// vault entries hold AES-GCM payloads that only the vault key can decrypt.
///
/// The schema mirrors Room schema version 3 (including the sync columns) so the connected-mode
/// phase needs no migration.
public final class AppDatabase: Sendable {
    let writer: any DatabaseWriter

    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// An on-disk database (WAL, so UI observation can read while a write is in flight).
    public static func open(at url: URL) throws -> AppDatabase {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try AppDatabase(DatabasePool(path: url.path))
    }

    /// A throwaway in-memory database, for tests and previews.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "vault_entries") { t in
                t.primaryKey("id", .text)
                // nonce(12) || ciphertext || tag(16); AAD is the entry id as UTF-8.
                t.column("encryptedPayload", .blob).notNull()
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .integer).notNull()
                t.column("updatedAt", .integer).notNull()
                t.column("deletedAt", .integer)
                t.column("pendingSync", .boolean).notNull().defaults(to: false)
                t.column("entryVersion", .integer).notNull().defaults(to: 0)   // server version, 0 = never synced
                t.column("serverUpdatedAt", .text)                             // server's ISO timestamp
            }

            try db.create(table: "settings") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }

            try db.create(table: "entry_usage") { t in
                t.primaryKey("entryId", .text)
                t.column("lastUsedAt", .integer).notNull()
                t.column("useCount", .integer).notNull()
            }
        }

        return migrator
    }
}
