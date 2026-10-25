import Foundation
import GRDB

/// Encrypted vault entry as stored in SQLite. Timestamps are Unix milliseconds, like Android.
public struct VaultEntryRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "vault_entries"

    public var id: String
    public var encryptedPayload: Data
    public var sortOrder: Int
    public var createdAt: Int64
    public var updatedAt: Int64
    public var deletedAt: Int64?
    public var pendingSync: Bool
    public var entryVersion: Int
    public var serverUpdatedAt: String?

    public init(
        id: String,
        encryptedPayload: Data,
        sortOrder: Int = 0,
        createdAt: Int64,
        updatedAt: Int64,
        deletedAt: Int64? = nil,
        pendingSync: Bool = false,
        entryVersion: Int = 0,
        serverUpdatedAt: String? = nil
    ) {
        self.id = id
        self.encryptedPayload = encryptedPayload
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.pendingSync = pendingSync
        self.entryVersion = entryVersion
        self.serverUpdatedAt = serverUpdatedAt
    }
}

/// Key-value settings row (see ``SettingsKeys``).
public struct SettingsRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "settings"

    public var key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

/// Local-only usage statistics, used for the "recently used" / "most used" sort modes.
public struct EntryUsageRecord: Codable, Equatable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "entry_usage"

    public var entryId: String
    public var lastUsedAt: Int64
    public var useCount: Int

    public init(entryId: String, lastUsedAt: Int64, useCount: Int) {
        self.entryId = entryId
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
    }
}
