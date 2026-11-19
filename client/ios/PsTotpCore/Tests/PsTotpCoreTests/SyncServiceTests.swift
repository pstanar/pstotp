import Foundation
import GRDB
import Testing
@testable import PsTotpCore

/// The parts of the server's vault API the sync uses, with its real version/delete/reorder rules
/// (src/Server.Api/EndPoints/VaultEndpoints.cs).
final class FakeVaultServer: HTTPTransport, @unchecked Sendable {
    struct Entry {
        var payload: String; var version: Int; var deleted: Bool; var sortOrder: Int; var updatedAt = "2026-11-19T10:00:00Z"
    }
    private let lock = NSLock()
    private var _entries: [String: Entry] = [:]
    private(set) var log: [String] = []
    var offline = false
    var failDeletesWith: Int?
    /// Runs while a PUT is "in flight" — to simulate an edit made during the request.
    var duringPut: (@Sendable (String) async -> Void)?

    var entries: [String: Entry] { get { lock.withLock { _entries } } set { lock.withLock { _entries = newValue } } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if offline { throw URLError(.notConnectedToInternet) }
        let method = request.httpMethod ?? "GET"
        let path = request.url!.path.replacingOccurrences(of: "/api", with: "")
        lock.withLock { log.append("\(method) \(path)") }
        let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]

        func reply(_ status: Int, _ object: Any = [String: Any]()) throws -> (Data, HTTPURLResponse) {
            let data = try JSONSerialization.data(withJSONObject: object)
            return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                          headerFields: ["Content-Type": "application/json"])!)
        }

        switch (method, path) {
        case ("GET", "/vault"):
            let list = entries.sorted { $0.key < $1.key }.map { id, e -> [String: Any] in
                ["id": id, "entryPayload": e.payload, "entryVersion": e.version,
                 "deletedAt": e.deleted ? "2026-11-19T09:00:00Z" : NSNull(), "updatedAt": e.updatedAt, "sortOrder": e.sortOrder]
            }
            return try reply(200, ["entries": list, "serverTime": "2026-11-19T12:00:00Z"])
        case ("POST", "/vault/reorder"):
            let ids = body["entryIds"] as? [String] ?? []
            lock.withLock {
                for (index, id) in ids.enumerated() where _entries[id]?.deleted == false { _entries[id]!.sortOrder = index }
            }
            return try reply(200)
        case ("PUT", _) where path.hasPrefix("/vault/"):
            let id = String(path.dropFirst("/vault/".count))
            await duringPut?(id)
            let payload = body["entryPayload"] as? String ?? ""
            let version = body["entryVersion"] as? Int ?? 0
            return try lock.withLock {
                if var existing = _entries[id] {
                    guard existing.version == version else { return try reply(409, ["detail": "Version conflict"]) }
                    existing.payload = payload; existing.version += 1; existing.updatedAt = "2026-11-19T11:00:00Z"
                    _entries[id] = existing
                    return try reply(200, ["id": id, "entryVersion": existing.version, "updatedAt": existing.updatedAt])
                }
                let sort = (_entries.values.filter { !$0.deleted }.map(\.sortOrder).max() ?? -1) + 1
                _entries[id] = Entry(payload: payload, version: 1, deleted: false, sortOrder: sort)
                return try reply(200, ["id": id, "entryVersion": 1, "updatedAt": "2026-11-19T10:00:00Z"])
            }
        case ("DELETE", _) where path.hasPrefix("/vault/"):
            if let failDeletesWith { return try reply(failDeletesWith, ["detail": "boom"]) }
            let id = String(path.dropFirst("/vault/".count))
            return try lock.withLock {
                guard _entries[id] != nil else { return try reply(404) }
                _entries[id]!.deleted = true; _entries[id]!.version += 1
                return try reply(200)
            }
        default:
            return try reply(404)
        }
    }
}

@Suite("SyncService")
struct SyncServiceTests {
    let db: AppDatabase
    let repo: VaultRepository
    let server = FakeVaultServer()
    let client: ApiClient
    let sync: SyncService
    let key = KeyDerivation.generateVaultKey()

    init() async throws {
        db = try AppDatabase.inMemory()
        repo = VaultRepository(db: db)
        client = ApiClient(baseURL: "https://x.test/api", transport: server)
        await client.setTokens(access: "AT", refresh: "RT")
        sync = SyncService(db: db, client: client, repository: repo)
        try await repo.setSetting(SettingsKeys.mode, SettingsKeys.modeConnected)
    }

    private func plain(_ issuer: String) -> VaultEntryPlaintext {
        VaultEntryPlaintext(issuer: issuer, accountName: "me", secret: "JBSWY3DPEHPK3PXP")
    }

    @discardableResult
    private func addLocal(_ issuer: String) async throws -> VaultEntry {
        try await repo.addEntry(vaultKey: key, plaintext: plain(issuer))
    }

    /// An entry as another device would have pushed it.
    private func serverEntry(_ issuer: String, id: String = UUID().uuidString.lowercased(), version: Int = 1, sort: Int = 0) throws -> String {
        let payload = try VaultRepository.encryptPayload(vaultKey: key, id: id, plaintext: plain(issuer))
        server.entries[id] = .init(payload: payload.base64EncodedString(), version: version, deleted: false, sortOrder: sort)
        return id
    }

    private func records() async throws -> [VaultEntryRecord] {
        try await db.writer.read { try VaultEntryRecord.fetchAll($0).sorted { $0.sortOrder < $1.sortOrder } }
    }

    private func issuers() async throws -> [String] { try await repo.getAllEntries(vaultKey: key).map(\.issuer) }

    // MARK: Push

    @Test func pushesNewEntriesAndRecordsTheServerVersion() async throws {
        let entry = try await addLocal("GitHub")
        #expect(await sync.fullSync() == .success(pulled: 0, pushed: 1))
        #expect(server.entries[entry.id]?.version == 1)
        let record = try #require(try await records().first)
        #expect(record.pendingSync == false && record.entryVersion == 1 && record.serverUpdatedAt == "2026-11-19T10:00:00Z")
        #expect(try await repo.getSetting(SettingsKeys.lastSyncAt) == "2026-11-19T12:00:00Z")
    }

    @Test func aSecondSyncWithNothingToDoPushesNothing() async throws {
        try await addLocal("GitHub")
        _ = await sync.fullSync()
        #expect(await sync.fullSync() == .success(pulled: 0, pushed: 0))
        #expect(server.log.filter { $0.hasPrefix("PUT") }.count == 1)
    }

    @Test func editsGoOutWithTheKnownVersion() async throws {
        let entry = try await addLocal("GitHub")
        _ = await sync.fullSync()
        let edited = EntryValidation.edited(entry, issuer: "GitHub Inc", accountName: "me", icon: nil)
        try await repo.updateEntry(vaultKey: key, entry: edited)
        #expect(await sync.fullSync() == .success(pulled: 0, pushed: 1))
        #expect(server.entries[entry.id]?.version == 2)
        #expect(try await issuers() == ["GitHub Inc"])
    }

    @Test func conflictLetsTheServerVersionWin() async throws {
        let entry = try await addLocal("GitHub")
        _ = await sync.fullSync()
        // Another device edits first (version 2); we edit the stale version 1.
        let theirs = try VaultRepository.encryptPayload(vaultKey: key, id: entry.id, plaintext: plain("Theirs"))
        server.entries[entry.id]?.payload = theirs.base64EncodedString()
        server.entries[entry.id]?.version = 2
        let mine = EntryValidation.edited(entry, issuer: "Mine", accountName: "me", icon: nil)
        try await repo.updateEntry(vaultKey: key, entry: mine)

        #expect(await sync.fullSync() == .success(pulled: 1, pushed: 0))
        #expect(try await issuers() == ["Theirs"])
        let record = try #require(try await records().first)
        #expect(record.entryVersion == 2 && record.pendingSync == false)
    }

    @Test func anEditMadeDuringThePushStaysPending() async throws {
        let entry = try await addLocal("GitHub")
        let (repo, key) = (self.repo, self.key)
        server.duringPut = { _ in
            let edited = EntryValidation.edited(entry, issuer: "Edited meanwhile", accountName: "me", icon: nil)
            try? await repo.updateEntry(vaultKey: key, entry: edited)
        }
        _ = await sync.fullSync()
        server.duringPut = nil
        let record = try #require(try await records().first)
        #expect(record.pendingSync == true && record.entryVersion == 1)
        #expect(await sync.fullSync() == .success(pulled: 0, pushed: 1))   // goes out next time
        #expect(server.entries[entry.id]?.version == 2)
    }

    @Test func changesMadeWhileDisconnectedAreSentWhenTheDeviceReconnects() async throws {
        let synced = try await addLocal("Synced")
        let gone = try await addLocal("Gone")
        _ = await sync.fullSync()                                       // both on the server

        // Disconnect (mode standalone), then edit, add and delete.
        try await repo.setSetting(SettingsKeys.mode, SettingsKeys.modeStandalone)
        let edited = EntryValidation.edited(synced, issuer: "Edited offline", accountName: "me", icon: nil)
        try await repo.updateEntry(vaultKey: key, entry: edited)
        let added = try await addLocal("Added offline")
        try await repo.deleteEntry(id: gone.id)

        // Reconnect to the same account: nothing re-encrypts, but the changes were remembered.
        try await repo.setSetting(SettingsKeys.mode, SettingsKeys.modeConnected)
        guard case .success(_, let pushed) = await sync.fullSync() else { Issue.record("sync failed"); return }
        #expect(pushed == 3)                                            // the edit, the addition, the deletion
        #expect(server.entries[added.id] != nil)
        #expect(server.entries[gone.id]?.deleted == true)
        #expect(server.entries[synced.id]?.version == 2)
        #expect(try await issuers() == ["Edited offline", "Added offline"])
    }

    // MARK: Deletions

    @Test func localDeletionIsPushedThenForgotten() async throws {
        let entry = try await addLocal("GitHub")
        _ = await sync.fullSync()
        try await repo.deleteEntry(id: entry.id)
        #expect(await sync.fullSync() == .success(pulled: 0, pushed: 1))
        #expect(server.entries[entry.id]?.deleted == true)
        #expect(try await records().isEmpty)
        #expect(await sync.fullSync() == .success(pulled: 0, pushed: 0))   // doesn't come back
    }

    @Test func deletingSomethingTheServerNeverHadJustDropsIt() async throws {
        let entry = try await addLocal("Local only")
        try await repo.deleteEntry(id: entry.id)
        #expect(await sync.fullSync() == .success(pulled: 0, pushed: 1))
        #expect(try await records().isEmpty)
    }

    @Test func aFailedDeletionKeepsTheTombstoneSoTheEntryDoesNotComeBack() async throws {
        let entry = try await addLocal("GitHub")
        _ = await sync.fullSync()
        try await repo.deleteEntry(id: entry.id)

        server.failDeletesWith = 500
        guard case .error = await sync.fullSync() else { Issue.record("expected an error"); return }
        #expect(try await records().count == 1)                     // tombstone still there
        #expect(try await issuers().isEmpty)

        server.failDeletesWith = nil
        #expect(await sync.fullSync() == .success(pulled: 0, pushed: 1))
        #expect(server.entries[entry.id]?.deleted == true)
        #expect(try await records().isEmpty)
    }

    @Test func offlineKeepsEverythingPendingAndSucceedsLater() async throws {
        let entry = try await addLocal("GitHub")
        try await repo.deleteEntry(id: (try await addLocal("Gone")).id)
        server.offline = true
        #expect(await sync.fullSync() == .error("Could not reach the server."))
        #expect(try await records().filter(\.pendingSync).count == 2)
        server.offline = false
        _ = await sync.fullSync()
        #expect(server.entries[entry.id] != nil)
        #expect(try await issuers() == ["GitHub"])
    }

    // MARK: Pull

    @Test func pullsNewServerEntriesAndTheyDecrypt() async throws {
        _ = try serverEntry("AWS", sort: 0)
        _ = try serverEntry("Google", sort: 1)
        #expect(await sync.fullSync() == .success(pulled: 2, pushed: 0))
        #expect(try await issuers() == ["AWS", "Google"])
        #expect(try await records().allSatisfy { !$0.pendingSync && $0.entryVersion == 1 })
    }

    @Test func pullReplacesAnOlderLocalVersion() async throws {
        let id = try serverEntry("Old", version: 1)
        _ = await sync.fullSync()
        let payload = try VaultRepository.encryptPayload(vaultKey: key, id: id, plaintext: plain("New"))
        server.entries[id]?.payload = payload.base64EncodedString()
        server.entries[id]?.version = 2
        #expect(await sync.fullSync() == .success(pulled: 1, pushed: 0))
        #expect(try await issuers() == ["New"])
    }

    @Test func serverDeletionsRemoveTheLocalEntry() async throws {
        let id = try serverEntry("Doomed")
        _ = await sync.fullSync()
        server.entries[id]?.deleted = true
        server.entries[id]?.version = 2
        _ = await sync.fullSync()
        #expect(try await issuers().isEmpty)
        // …and a tombstone that arrives for an entry we never had is ignored.
        let other = try serverEntry("Never seen")
        server.entries[other]?.deleted = true
        _ = await sync.fullSync()
        #expect(try await records().count == 1)
    }

    @Test func reorderingOnAnotherDeviceIsApplied() async throws {
        let a = try serverEntry("A", sort: 0), b = try serverEntry("B", sort: 1)
        _ = await sync.fullSync()
        #expect(try await issuers() == ["A", "B"])
        server.entries[a]?.sortOrder = 1     // no version change, as on the real server
        server.entries[b]?.sortOrder = 0
        _ = await sync.fullSync()
        #expect(try await issuers() == ["B", "A"])
    }

    @Test func aLocalReorderIsPushedBeforeThePullCouldUndoIt() async throws {
        let a = try serverEntry("A", sort: 0), b = try serverEntry("B", sort: 1)
        _ = await sync.fullSync()
        try await repo.reorderEntries(orderedIds: [b, a])
        #expect(await sync.fullSync() == .success(pulled: 0, pushed: 0))
        #expect(server.entries[b]?.sortOrder == 0 && server.entries[a]?.sortOrder == 1)
        #expect(try await issuers() == ["B", "A"])
        #expect(try await repo.isPendingReorder() == false)
    }

    @Test func pushingNewEntriesAlsoPushesTheOrder() async throws {
        let first = try await addLocal("First"), second = try await addLocal("Second")
        _ = await sync.fullSync()
        #expect(server.log.contains("POST /vault/reorder"))
        #expect(server.entries[first.id]?.sortOrder == 0 && server.entries[second.id]?.sortOrder == 1)
    }

    @Test func aPendingLocalEditIsNotOverwrittenByAnOlderPull() async throws {
        let entry = try await addLocal("Mine")
        // Pretend the push can't happen: pull only.
        server.entries[entry.id] = .init(
            payload: try VaultRepository.encryptPayload(vaultKey: key, id: entry.id, plaintext: plain("Server")).base64EncodedString(),
            version: 5, deleted: false, sortOrder: 0)
        _ = try await sync.pullVault()
        #expect(try await issuers() == ["Mine"])
    }

    // MARK: Session

    @Test func notConnectedWithoutTokens() async throws {
        await client.clearTokens()
        #expect(await sync.fullSync() == .notConnected)
        #expect(server.log.isEmpty)
    }

    @Test func aRejectedRefreshReportsAnExpiredSession() async throws {
        // The first request is rejected and so is the token refresh.
        let expiredClient = ApiClient(baseURL: "https://x.test/api", transport: StubTransport([.init(status: 401), .init(status: 401)]))
        await expiredClient.setTokens(access: "AT", refresh: "RT")
        try await addLocal("Pending")
        let service = SyncService(db: db, client: expiredClient, repository: repo)
        #expect(await service.fullSync() == .sessionExpired)
        #expect(try await records().first?.pendingSync == true)   // nothing lost
    }
}
