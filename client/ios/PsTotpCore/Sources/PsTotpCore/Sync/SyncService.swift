import Foundation
import GRDB

public enum SyncResult: Equatable, Sendable {
    case success(pulled: Int, pushed: Int)
    case error(String)
    case notConnected
    case sessionExpired
}

/// Vault sync: pushes local changes, then pulls the server's state (Android's `SyncService`).
///
/// The server's `entryPayload` (base64) decodes to the same bytes as the local `encryptedPayload`
/// (`nonce || ciphertext+tag`, AAD = entry id), so nothing is re-encrypted: the vault key is the same
/// on every device. Push goes first so stale server data can't overwrite local edits. An actor, so two
/// triggers can't run a sync at the same time.
public actor SyncService {
    private let db: AppDatabase
    private let client: ApiClient
    private let vaultApi: VaultApi
    private let repository: VaultRepository
    private let now: @Sendable () -> Int64

    public init(
        db: AppDatabase, client: ApiClient, repository: VaultRepository,
        now: @escaping @Sendable () -> Int64 = VaultRepository.systemNow
    ) {
        self.db = db
        self.client = client
        self.vaultApi = VaultApi(client: client)
        self.repository = repository
        self.now = now
    }

    public func fullSync() async -> SyncResult {
        guard await client.hasTokens else { return .notConnected }
        do {
            let pushed = try await pushAllPending()
            let pulled = try await pullVault()
            return .success(pulled: pulled, pushed: pushed)
        } catch ApiError.sessionExpired {
            return .sessionExpired
        } catch let error as ApiError {
            return .error(error.message)
        } catch {
            return .error(error.localizedDescription)
        }
    }

    // MARK: Pull

    /// Merges the server's entries into the local database, in one transaction. Returns how many
    /// entries were added or replaced.
    func pullVault() async throws -> Int {
        let response = try await vaultApi.fetchVault()
        let timestamp = now()
        return try await db.writer.write { db in
            let local = Dictionary(uniqueKeysWithValues: try VaultEntryQueries.allIncludingDeleted(db).map { ($0.id, $0) })
            var pulled = 0
            for server in response.entries {
                let existing = local[server.id]

                if server.deletedAt != nil {
                    if let existing, existing.deletedAt == nil {
                        try VaultEntryQueries.softDelete(db, id: server.id, timestamp: timestamp)
                    }
                    continue
                }
                guard let payload = Data(base64Encoded: server.entryPayload) else { continue }   // unreadable: leave it

                guard var existing else {
                    try VaultEntryQueries.upsert(db, VaultEntryRecord(
                        id: server.id, encryptedPayload: payload, sortOrder: server.sortOrder,
                        createdAt: timestamp, updatedAt: timestamp,
                        entryVersion: server.entryVersion, serverUpdatedAt: server.updatedAt))
                    pulled += 1
                    continue
                }
                guard !existing.pendingSync else { continue }   // our edit wins until it has been pushed

                if server.entryVersion > existing.entryVersion {
                    existing.encryptedPayload = payload
                    existing.sortOrder = server.sortOrder
                    existing.updatedAt = timestamp
                    existing.entryVersion = server.entryVersion
                    existing.serverUpdatedAt = server.updatedAt
                    try VaultEntryQueries.upsert(db, existing)
                    pulled += 1
                } else if existing.deletedAt == nil, existing.sortOrder != server.sortOrder {
                    // A reorder on another device doesn't change the entry version.
                    try VaultEntryQueries.updateSortOrder(db, id: existing.id, sortOrder: server.sortOrder)
                    pulled += 1
                }
            }
            try SettingsQueries.set(db, SettingsKeys.lastSyncAt, response.serverTime)
            return pulled
        }
    }

    // MARK: Push

    /// Pushes every locally modified entry, then the order if anything was pushed or a reorder is
    /// pending. Returns how many entries were pushed.
    func pushAllPending() async throws -> Int {
        let pending = try await db.writer.read { try VaultEntryQueries.pendingSync($0) }
        var pushed = 0
        for record in pending {
            if try await push(record) { pushed += 1 }
        }

        let reorderPending = try await repository.isPendingReorder()
        if pushed > 0 || reorderPending {
            let ids = try await db.writer.read { try VaultEntryQueries.liveIdsInOrder($0) }
            try await vaultApi.reorderEntries(entryIds: ids)
            try await repository.clearPendingReorder()
        }
        return pushed
    }

    /// - Returns: false on a version conflict (the server's copy wins at the next pull).
    private func push(_ record: VaultEntryRecord) async throws -> Bool {
        if record.deletedAt != nil {
            do {
                try await vaultApi.deleteEntry(entryId: record.id)
            } catch ApiError.http(404, _) {
                // The server never had it: nothing to delete there.
            }
            // Any other failure (offline, server error) propagates: the tombstone stays and is
            // retried, instead of the entry coming back at the next pull.
            try await db.writer.write { try VaultEntryQueries.hardDelete($0, id: record.id) }
            return true
        }

        do {
            let response = try await vaultApi.upsertEntry(
                entryId: record.id, entryPayload: record.encryptedPayload.base64EncodedString(),
                entryVersion: record.entryVersion)
            try await markSynced(record, version: response.entryVersion, serverUpdatedAt: response.updatedAt)
            return true
        } catch ApiError.conflict {
            // The server has a newer version: drop our pending flag so the pull replaces this entry.
            try await markSynced(record, version: record.entryVersion, serverUpdatedAt: record.serverUpdatedAt)
            return false
        }
    }

    /// Records the server's version. The pending flag is cleared only if the entry is unchanged since
    /// it was read: an edit made during the request stays pending and goes out at the next sync.
    private func markSynced(_ pushed: VaultEntryRecord, version: Int, serverUpdatedAt: String?) async throws {
        try await db.writer.write { db in
            guard var current = try VaultEntryQueries.byId(db, pushed.id) else { return }
            current.entryVersion = version
            current.serverUpdatedAt = serverUpdatedAt
            if current.encryptedPayload == pushed.encryptedPayload && current.deletedAt == pushed.deletedAt {
                current.pendingSync = false
            }
            try VaultEntryQueries.upsert(db, current)
        }
    }
}
