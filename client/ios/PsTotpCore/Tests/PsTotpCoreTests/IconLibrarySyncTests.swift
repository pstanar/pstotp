import Foundation
import Testing
@testable import PsTotpCore

/// The icon-library endpoints with the server's rules (VaultIconLibraryEndpoints.cs): one row per
/// user, `expectedVersion` must match (0 for the first write), 409 otherwise.
final class FakeIconLibraryServer: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _payload = ""
    private var _version = 0
    private(set) var log: [String] = []
    var offline = false
    /// Runs while a PUT is in flight.
    var duringPut: (@Sendable () async -> Void)?

    var payload: String { lock.withLock { _payload } }
    var version: Int { lock.withLock { _version } }
    func set(payload: String, version: Int) { lock.withLock { _payload = payload; _version = version } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if offline { throw URLError(.notConnectedToInternet) }
        let method = request.httpMethod ?? "GET"
        lock.withLock { log.append(method) }
        func reply(_ status: Int, _ object: [String: Any]) throws -> (Data, HTTPURLResponse) {
            (try JSONSerialization.data(withJSONObject: object),
             HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }
        if method == "GET" {
            return try lock.withLock {
                try reply(200, _version == 0 ? ["encryptedPayload": "", "version": 0]
                                             : ["encryptedPayload": _payload, "version": _version, "updatedAt": "2026-11-19T10:00:00Z"])
            }
        }
        await duringPut?()
        let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
        return try lock.withLock {
            guard body["expectedVersion"] as? Int == _version else { return try reply(409, ["detail": "Library was modified on another device"]) }
            _payload = body["encryptedPayload"] as? String ?? ""
            _version += 1
            return try reply(200, ["version": _version, "updatedAt": "2026-11-19T11:00:00Z"])
        }
    }
}

@Suite("IconLibrarySyncService")
struct IconLibrarySyncTests {
    let db: AppDatabase
    let library: IconLibraryRepository
    let server = FakeIconLibraryServer()
    let sync: IconLibrarySyncService
    let key = KeyDerivation.generateVaultKey()

    init() throws {
        db = try AppDatabase.inMemory()
        library = IconLibraryRepository(db: db)
        sync = IconLibrarySyncService(library: library, client: ApiClient(baseURL: "https://x.test/api", transport: server))
    }

    private func icon(_ n: Int, label: String? = nil) -> LibraryIcon {
        let data = "data:image/png;base64,AAAA\(n)"
        return LibraryIcon(id: "id-\(n)", label: label ?? "Icon \(n)", data: data, createdAt: "t",
                           dataHash: Hash.sha256Hex(Data(data.utf8)))
    }

    private func put(_ icons: [LibraryIcon], version: Int) throws {
        let payload = try IconLibraryCrypto.encrypt(vaultKey: key, blob: IconLibraryBlob(icons: icons))
        server.set(payload: payload.base64EncodedString(), version: version)
    }

    private func serverIcons() throws -> [String] {
        let payload = try #require(Data(base64Encoded: server.payload))
        return try IconLibraryCrypto.decrypt(vaultKey: key, payload: payload).icons.map(\.id)
    }

    // MARK: Push

    @Test func theFirstLibraryIsCreatedOnAnEmptyServer() async throws {
        try await library.save(vaultKey: key, icons: [icon(1)])
        let icons = try await sync.sync(vaultKey: key)
        #expect(icons.map(\.id) == ["id-1"])
        let ids = try serverIcons()
        #expect(server.version == 1 && ids == ["id-1"])
        let (dirty, version) = (try await library.isDirty(), try await library.serverVersion())
        #expect(!dirty && version == 1)
    }

    @Test func nothingToDoTouchesOnlyTheReadEndpoint() async throws {
        try put([icon(1)], version: 3)
        _ = try await sync.sync(vaultKey: key)            // adopts version 3
        _ = try await sync.sync(vaultKey: key)
        #expect(server.log == ["GET", "GET"])
        #expect(try await library.serverVersion() == 3)
    }

    @Test func aLocalChangeWinsOverTheServerCopyOnceVersionsAreKnown() async throws {
        try put([icon(1)], version: 1)
        _ = try await sync.sync(vaultKey: key)             // adopt
        try await library.save(vaultKey: key, icons: [icon(1), icon(2)])
        #expect(try await sync.sync(vaultKey: key).map(\.id) == ["id-1", "id-2"])
        let ids = try serverIcons()
        #expect(server.version == 2 && ids == ["id-1", "id-2"])
        #expect(server.log == ["GET", "PUT"])               // known version: no read first
    }

    @Test func aVersionConflictRefetchesAndPutsAgain() async throws {
        try put([icon(1)], version: 1)
        _ = try await sync.sync(vaultKey: key)
        try put([icon(1), icon(9)], version: 2)             // another device pushed
        try await library.save(vaultKey: key, icons: [icon(1), icon(2)])
        _ = try await sync.sync(vaultKey: key)
        #expect(try serverIcons() == ["id-1", "id-2"])      // last write wins
        let version = try await library.serverVersion()
        #expect(server.version == 3 && version == 3)
    }

    @Test func aChangeMadeDuringThePushStaysDirty() async throws {
        try put([icon(1)], version: 1)
        _ = try await sync.sync(vaultKey: key)
        try await library.save(vaultKey: key, icons: [icon(1), icon(2)])
        let (library, key) = (self.library, self.key)
        server.duringPut = { try? await library.save(vaultKey: key, icons: [icon(1), icon(2), icon(3)]) }
        _ = try await sync.sync(vaultKey: key)
        server.duringPut = nil
        #expect(try await library.isDirty())
        _ = try await sync.sync(vaultKey: key)
        #expect(try serverIcons() == ["id-1", "id-2", "id-3"])
    }

    // MARK: First contact

    @Test func firstContactMergesInsteadOfOverwritingEitherLibrary() async throws {
        try put([icon(1), icon(2)], version: 4)             // the account's icons
        // Ours: icon 2 again (same content under another id) and a new icon 3.
        var duplicate = icon(2); duplicate.id = "local-2"
        try await library.save(vaultKey: key, icons: [duplicate, icon(3)])

        let icons = try await sync.sync(vaultKey: key)
        #expect(icons.map(\.id) == ["id-1", "id-2", "id-3"])
        #expect(try serverIcons() == ["id-1", "id-2", "id-3"])
        #expect(server.version == 5)
        let (dirty, version) = (try await library.isDirty(), try await library.serverVersion())
        #expect(!dirty && version == 5)
    }

    @Test func firstContactWithNothingNewJustAdoptsTheServerCopy() async throws {
        try put([icon(1), icon(2)], version: 2)
        try await library.save(vaultKey: key, icons: [icon(2)])
        #expect(try await sync.sync(vaultKey: key).map(\.id) == ["id-1", "id-2"])
        #expect(server.log == ["GET"])                      // no PUT
        let (dirty, version) = (try await library.isDirty(), try await library.serverVersion())
        #expect(!dirty && version == 2)
    }

    @Test func aServerLibraryThatTheKeyCantReadIsNotOverwritten() async throws {
        server.set(payload: Data(repeating: 7, count: 60).base64EncodedString(), version: 2)
        try await library.save(vaultKey: key, icons: [icon(1)])
        await #expect(throws: (any Error).self) { _ = try await sync.sync(vaultKey: key) }
        #expect(server.version == 2 && !server.log.contains("PUT"))
        #expect(try await library.isDirty())                // our change is still waiting
    }

    // MARK: Pull & failures

    @Test func aNewerServerLibraryIsAdopted() async throws {
        try put([icon(1)], version: 1)
        _ = try await sync.sync(vaultKey: key)
        try put([icon(1), icon(2)], version: 2)
        #expect(try await sync.sync(vaultKey: key).map(\.id) == ["id-1", "id-2"])
        #expect(try await library.serverVersion() == 2)
    }

    @Test func offlineLeavesTheLocalLibraryAlone() async throws {
        try await library.save(vaultKey: key, icons: [icon(1)])
        server.offline = true
        await #expect(throws: ApiError.network("Could not reach the server.")) { _ = try await sync.sync(vaultKey: key) }
        #expect(try await library.isDirty())
        #expect(try await library.load(vaultKey: key).map(\.id) == ["id-1"])
    }

    @Test func noLibraryAnywhereIsFine() async throws {
        #expect(try await sync.sync(vaultKey: key).isEmpty)
        #expect(server.version == 0 && !server.log.contains("PUT"))
    }

    // MARK: Merge rules

    @Test func mergeRespectsTheCountCap() {
        let server = (0..<IconLibraryLimits.maxIcons - 1).map { icon($0) }
        let local = [icon(1000), icon(1001), icon(1002)]
        let merged = IconDedup.merge(server: server, local: local)
        #expect(merged.count == IconLibraryLimits.maxIcons)
        #expect(merged.last?.id == "id-1000")
    }

    @Test func mergeMatchesOnSourceHashToo() {
        var theirs = icon(1); theirs.sourceHash = "same-source"
        var ours = icon(2); ours.sourceHash = "same-source"
        #expect(IconDedup.merge(server: [theirs], local: [ours]).map(\.id) == ["id-1"])
    }
}
