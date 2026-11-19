import Foundation

/// Keeps the icon library ("My icons") in step with the server (Android's `IconLibraryRepository`
/// push/pull + `IconLibrarySync`). The server holds one encrypted blob with an optimistic version.
///
/// - Library changed here and the server knows our version: our copy wins (last write wins, like the
///   web client). A version conflict refetches the current version and pushes again.
/// - First contact (this device never synced) with local icons: the two libraries are merged, so
///   connecting never wipes the account's icons — or ours.
/// - Otherwise the server's copy is adopted when it differs.
public actor IconLibrarySyncService {
    private let library: IconLibraryRepository
    private let api: IconLibraryApi

    public init(library: IconLibraryRepository, client: ApiClient) {
        self.library = library
        self.api = IconLibraryApi(client: client)
    }

    /// Push local changes, pull the server's, and return the resulting library.
    /// Throws on network / server errors; the local copy is left as it was.
    public func sync(vaultKey: Data) async throws -> [LibraryIcon] {
        let dirty = try await library.isDirty()
        let localVersion = try await library.serverVersion()
        let local = try await library.storedCiphertext()

        if dirty, localVersion > 0, let local {
            try await push(local, expectedVersion: localVersion)
            return try await library.load(vaultKey: vaultKey)
        }

        let server = try await api.fetch()
        if server.version == 0 || server.encryptedPayload.isEmpty {
            if dirty, let local { try await push(local, expectedVersion: server.version) }
            return try await library.load(vaultKey: vaultKey)
        }

        if dirty, local != nil {
            try await mergeWithServer(server, vaultKey: vaultKey)
        } else if server.version != localVersion || local == nil {
            try await library.adopt(ciphertext: server.encryptedPayload, version: server.version)
        }
        return try await library.load(vaultKey: vaultKey)
    }

    private func mergeWithServer(_ server: IconLibraryResponse, vaultKey: Data) async throws {
        guard let payload = Data(base64Encoded: server.encryptedPayload) else { throw CryptoError.invalidEncoding }
        let serverIcons = IconDedup.backfillHashes(try IconLibraryCrypto.decrypt(vaultKey: vaultKey, payload: payload).icons)
        let localIcons = try await library.load(vaultKey: vaultKey)
        let merged = IconDedup.merge(server: serverIcons, local: localIcons)

        if merged.count == serverIcons.count {
            try await library.adopt(ciphertext: server.encryptedPayload, version: server.version)   // nothing of ours is new
            return
        }
        try await library.save(vaultKey: vaultKey, icons: merged)
        guard let ciphertext = try await library.storedCiphertext() else { return }
        try await push(ciphertext, expectedVersion: server.version)
    }

    /// PUT; on a version conflict fetch the current version and put again (last write wins).
    private func push(_ ciphertext: String, expectedVersion: Int) async throws {
        let result: IconLibraryUpdateResponse
        do {
            result = try await api.update(encryptedPayload: ciphertext, expectedVersion: expectedVersion)
        } catch ApiError.conflict {
            let fresh = try await api.fetch()
            result = try await api.update(encryptedPayload: ciphertext, expectedVersion: fresh.version)
        }
        try await library.recordPushed(ciphertext, version: result.version)
    }
}
