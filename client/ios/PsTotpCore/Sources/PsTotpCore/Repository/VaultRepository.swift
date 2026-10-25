import Foundation
import GRDB

/// Handles vault encryption/decryption and persistence.
///
/// Entries are stored as AES-256-GCM encrypted JSON payloads. The entry ID is the associated data,
/// binding each ciphertext to its entry. The vault key is passed in per call and never stored here.
///
/// Not yet ported from Android: biometric key storage (needs Keychain / LocalAuthentication, lives
/// with the app target) and `runInTransaction` (only the sync service uses it).
public final class VaultRepository: Sendable {
    private let db: AppDatabase
    private let now: @Sendable () -> Int64

    /// - Parameter now: Clock in Unix milliseconds; injectable for tests.
    public init(db: AppDatabase, now: @escaping @Sendable () -> Int64 = VaultRepository.systemNow) {
        self.db = db
        self.now = now
    }

    public static let systemNow: @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }

    // MARK: Setup & unlock

    public func isSetUp() async throws -> Bool {
        try await db.writer.read { try SettingsQueries.isSetUp($0) }
    }

    /// Create the password, persist the salt/verifier/wrapped vault key atomically, and return the
    /// new vault key.
    public func setupPassword(_ password: String) async throws -> Data {
        let result = try await Self.offMainThread { try KeyDerivation.setupPassword(password) }

        // One transaction: a crash between the verifier and the wrapped key must not leave a vault
        // that reports itself set up but can never be unlocked.
        try await db.writer.write { db in
            try SettingsQueries.set(db, SettingsKeys.kdfSalt, result.salt.base64EncodedString())
            try SettingsQueries.set(db, SettingsKeys.passwordVerifier, result.verifier.base64EncodedString())
            try SettingsQueries.set(db, SettingsKeys.encryptedVaultKey, result.encryptedVaultKey.base64EncodedString())
            try SettingsQueries.set(db, SettingsKeys.mode, SettingsKeys.modeStandalone)
        }
        return result.vaultKey
    }

    /// - Returns: The vault key, or nil if the password is wrong or the vault isn't set up.
    public func unlockVault(password: String) async throws -> Data? {
        let stored = try await db.writer.read { db in
            (try SettingsQueries.get(db, SettingsKeys.kdfSalt),
             try SettingsQueries.get(db, SettingsKeys.passwordVerifier),
             try SettingsQueries.get(db, SettingsKeys.encryptedVaultKey))
        }
        guard let saltB64 = stored.0, let verifierB64 = stored.1, let encKeyB64 = stored.2 else { return nil }
        guard let salt = Data(base64Encoded: saltB64),
              let verifier = Data(base64Encoded: verifierB64),
              let encKey = Data(base64Encoded: encKeyB64)
        else { throw RepositoryError.corruptSettings }

        return try await Self.offMainThread {
            try KeyDerivation.unlockVault(
                password: password, salt: salt, storedVerifier: verifier, encryptedVaultKey: encKey)
        }
    }

    // MARK: Vault CRUD

    /// Decrypt all stored entries with the given vault key.
    ///
    /// Silently skipping undecryptable entries once hid a class of wrong-key bugs (the user saw an
    /// empty vault with no error). So a single sporadic failure is tolerated — rare storage
    /// corruption — but anything beyond that throws ``VaultKeyMismatchError``.
    public func getAllEntries(vaultKey: Data) async throws -> [VaultEntry] {
        let all = try await db.writer.read { try VaultEntryQueries.live($0) }
        if all.isEmpty { return [] }

        var decrypted = [VaultEntry]()
        var failures = 0
        for record in all {
            do { decrypted.append(try Self.decryptEntry(vaultKey: vaultKey, record: record)) }
            catch { failures += 1 }
        }

        if isVaultKeyMismatch(failures: failures, successes: decrypted.count) {
            throw VaultKeyMismatchError(failed: failures, total: all.count)
        }
        return decrypted
    }

    /// Live, ordered snapshots of the encrypted rows (decrypt with ``decrypt(vaultKey:records:)``).
    public func observeRecords() -> AsyncValueObservation<[VaultEntryRecord]> {
        VaultEntryQueries.observeLive().values(in: db.writer)
    }

    @discardableResult
    public func addEntry(vaultKey: Data, plaintext: VaultEntryPlaintext) async throws -> VaultEntry {
        // Lowercase: the id is the AES-GCM associated data and the server GUID, and Android/web
        // generate lowercase ids. Swift's `uuidString` is uppercase.
        let id = UUID().uuidString.lowercased()
        let timestamp = now()
        let encrypted = try Self.encryptPayload(vaultKey: vaultKey, id: id, plaintext: plaintext)

        let sortOrder = try await db.writer.write { db in
            let connected = try SettingsQueries.get(db, SettingsKeys.mode) == SettingsKeys.modeConnected
            let sortOrder = (try VaultEntryQueries.maxSortOrder(db) ?? -1) + 1
            try VaultEntryQueries.upsert(db, VaultEntryRecord(
                id: id,
                encryptedPayload: encrypted,
                sortOrder: sortOrder,
                createdAt: timestamp,
                updatedAt: timestamp,
                pendingSync: connected))
            return sortOrder
        }

        return VaultEntry(
            id: id,
            issuer: plaintext.issuer,
            accountName: plaintext.accountName,
            secret: plaintext.secret,
            algorithm: plaintext.algorithm,
            digits: plaintext.digits,
            period: plaintext.period,
            icon: plaintext.icon,
            sortOrder: sortOrder)
    }

    /// Re-encrypt and store an edited entry. Does nothing if the entry doesn't exist.
    public func updateEntry(vaultKey: Data, entry: VaultEntry) async throws {
        let plaintext = VaultEntryPlaintext(
            issuer: entry.issuer, accountName: entry.accountName, secret: entry.secret,
            algorithm: entry.algorithm, digits: entry.digits, period: entry.period, icon: entry.icon)
        let encrypted = try Self.encryptPayload(vaultKey: vaultKey, id: entry.id, plaintext: plaintext)
        let timestamp = now()

        try await db.writer.write { db in
            guard var existing = try VaultEntryQueries.byId(db, entry.id) else { return }
            existing.encryptedPayload = encrypted
            existing.updatedAt = timestamp
            existing.pendingSync = try SettingsQueries.get(db, SettingsKeys.mode) == SettingsKeys.modeConnected
            try VaultEntryQueries.upsert(db, existing)
        }
    }

    /// Soft-delete (so the deletion can sync) and forget local usage stats.
    public func deleteEntry(id: String) async throws {
        let timestamp = now()
        try await db.writer.write { db in
            let connected = try SettingsQueries.get(db, SettingsKeys.mode) == SettingsKeys.modeConnected
            try VaultEntryQueries.softDelete(db, id: id, timestamp: timestamp)
            if connected { try VaultEntryQueries.markPendingSync(db, id: id) }
            try EntryUsageQueries.delete(db, entryId: id)
        }
    }

    public func reorderEntries(orderedIds: [String]) async throws {
        try await db.writer.write { db in
            for (index, id) in orderedIds.enumerated() {
                try VaultEntryQueries.updateSortOrder(db, id: id, sortOrder: index)
            }
            if try SettingsQueries.get(db, SettingsKeys.mode) == SettingsKeys.modeConnected {
                try SettingsQueries.set(db, SettingsKeys.pendingReorder, "true")
            }
        }
    }

    // MARK: Usage tracking (local only)

    public func getAllUsage() async throws -> [EntryUsageRecord] {
        try await db.writer.read { try EntryUsageQueries.all($0) }
    }

    public func recordEntryUse(entryId: String) async throws {
        let timestamp = now()
        try await db.writer.write { try EntryUsageQueries.recordUse($0, entryId: entryId, now: timestamp) }
    }

    // MARK: Sync state

    public func isConnected() async throws -> Bool {
        try await getSetting(SettingsKeys.mode) == SettingsKeys.modeConnected
    }

    public func isPendingReorder() async throws -> Bool {
        try await getSetting(SettingsKeys.pendingReorder) == "true"
    }

    public func clearPendingReorder() async throws {
        try await deleteSetting(SettingsKeys.pendingReorder)
    }

    /// The encrypted payload as base64, for pushing to the server.
    public func getEntryPayloadBase64(entryId: String) async throws -> String? {
        try await db.writer.read { try VaultEntryQueries.byId($0, entryId) }?
            .encryptedPayload.base64EncodedString()
    }

    /// The server entry version (0 = never synced or unknown).
    public func getEntryVersion(entryId: String) async throws -> Int {
        try await db.writer.read { try VaultEntryQueries.byId($0, entryId) }?.entryVersion ?? 0
    }

    // MARK: Settings

    public func getSetting(_ key: String) async throws -> String? {
        try await db.writer.read { try SettingsQueries.get($0, key) }
    }

    public func setSetting(_ key: String, _ value: String) async throws {
        try await db.writer.write { try SettingsQueries.set($0, key, value) }
    }

    public func deleteSetting(_ key: String) async throws {
        try await db.writer.write { try SettingsQueries.delete($0, key) }
    }

    // MARK: Encryption helpers

    /// Decrypt rows previously delivered by ``observeRecords()``. Failures follow the same
    /// tolerance rule as ``getAllEntries(vaultKey:)``.
    public static func decrypt(vaultKey: Data, records: [VaultEntryRecord]) throws -> [VaultEntry] {
        var decrypted = [VaultEntry]()
        var failures = 0
        for record in records {
            do { decrypted.append(try decryptEntry(vaultKey: vaultKey, record: record)) }
            catch { failures += 1 }
        }
        if isVaultKeyMismatch(failures: failures, successes: decrypted.count) {
            throw VaultKeyMismatchError(failed: failures, total: records.count)
        }
        return decrypted
    }

    static func encryptPayload(vaultKey: Data, id: String, plaintext: VaultEntryPlaintext) throws -> Data {
        try AesGcm.encrypt(
            key: vaultKey, plaintext: try plaintextToJson(plaintext), associatedData: Data(id.utf8))
    }

    static func decryptEntry(vaultKey: Data, record: VaultEntryRecord) throws -> VaultEntry {
        let json = try AesGcm.decrypt(
            key: vaultKey, payload: record.encryptedPayload, associatedData: Data(record.id.utf8))
        let p = try jsonToPlaintext(json)
        return VaultEntry(
            id: record.id, issuer: p.issuer, accountName: p.accountName, secret: p.secret,
            algorithm: p.algorithm, digits: p.digits, period: p.period, icon: p.icon,
            version: 1, sortOrder: record.sortOrder)
    }

    static func plaintextToJson(_ p: VaultEntryPlaintext) throws -> Data {
        var obj: JSONObject = [
            "issuer": p.issuer, "accountName": p.accountName, "secret": p.secret,
            "algorithm": p.algorithm, "digits": p.digits, "period": p.period,
        ]
        if let icon = p.icon { obj["icon"] = icon }
        return try JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes])
    }

    static func jsonToPlaintext(_ json: Data) throws -> VaultEntryPlaintext {
        guard let obj = try JSONSerialization.jsonObject(with: json) as? JSONObject,
              let issuer = obj["issuer"] as? String,
              let accountName = obj["accountName"] as? String,
              let secret = obj["secret"] as? String
        else { throw RepositoryError.malformedPayload }
        return VaultEntryPlaintext(
            issuer: issuer, accountName: accountName, secret: secret,
            algorithm: obj.optString("algorithm", "SHA1"),
            digits: obj.optInt("digits", 6),
            period: obj.optInt("period", 30),
            icon: obj.optStringField("icon"))
    }

    /// Argon2 is deliberately expensive (64 MB, ~100+ ms); keep it off the caller's executor.
    private static func offMainThread<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await Task.detached(priority: .userInitiated, operation: work).value
    }
}

public enum RepositoryError: Error, Equatable {
    case corruptSettings
    case malformedPayload
}
