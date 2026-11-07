import Foundation
import GRDB

/// The icon library stored on this device: the blob lives in the settings table as the same
/// ciphertext the server would hold (AES-GCM under the vault key), so connected mode can sync it
/// later without converting anything. Standalone only for now: no server version tracking beyond
/// the keys, no push / pull.
public final class IconLibraryRepository: Sendable {
    private let db: AppDatabase
    private let makeId: @Sendable () -> String
    private let now: @Sendable () -> String

    public init(
        db: AppDatabase,
        makeId: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
        now: @escaping @Sendable () -> String = IconLibraryRepository.systemNow
    ) {
        self.db = db
        self.makeId = makeId
        self.now = now
    }

    /// `2026-04-22T00:00:00.000Z`, like JavaScript's `toISOString`.
    public static let systemNow: @Sendable () -> String = {
        Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted))
    }

    /// Read and decrypt the local blob; empty when none exists. A wrong key or damaged blob also
    /// reads as empty rather than failing, as on Android.
    public func load(vaultKey: Data) async throws -> [LibraryIcon] {
        let stored = try await db.writer.read { try SettingsQueries.get($0, SettingsKeys.iconLibraryCiphertext) }
        guard let stored, !stored.isEmpty, let payload = Data(base64Encoded: stored),
              let blob = try? IconLibraryCrypto.decrypt(vaultKey: vaultKey, payload: payload)
        else { return [] }
        return IconDedup.backfillHashes(blob.icons)
    }

    /// Encrypt and store `icons`, marking the library unsynced.
    public func save(vaultKey: Data, icons: [LibraryIcon]) async throws {
        let payload = try IconLibraryCrypto.encrypt(vaultKey: vaultKey, blob: IconLibraryBlob(icons: icons))
        try await db.writer.write { db in
            try SettingsQueries.set(db, SettingsKeys.iconLibraryCiphertext, payload.base64EncodedString())
            try SettingsQueries.set(db, SettingsKeys.iconLibraryDirty, "true")
        }
    }

    /// Add one icon, de-duplicated on content. A duplicate leaves `current` as it is.
    /// - Throws: `IconLibraryError` when a cap would be exceeded.
    public func add(vaultKey: Data, current: [LibraryIcon], input: IconInput) async throws -> [LibraryIcon] {
        switch IconDedup.planAdd(current: current, input: input, makeId: makeId, now: now) {
        case .duplicate: return current
        case .countCapExceeded: throw IconLibraryError.countCapExceeded
        case .byteCapExceeded: throw IconLibraryError.byteCapExceeded
        case .added(let icons):
            try await save(vaultKey: vaultKey, icons: icons)
            return icons
        }
    }

    /// Add many icons in one write, de-duplicating against the library and within the batch.
    public func addBatch(
        vaultKey: Data, current: [LibraryIcon], items: [IconInput]
    ) async throws -> (icons: [LibraryIcon], result: IconBatchResult) {
        let planned = IconDedup.planBatch(current: current, items: items, makeId: makeId, now: now)
        if planned.result.added > 0 { try await save(vaultKey: vaultKey, icons: planned.icons) }
        return planned
    }
}
