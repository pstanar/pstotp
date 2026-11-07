import Foundation
import Testing
@testable import PsTotpCore

@Suite("Icon library")
struct IconLibraryTests {
    static let key = Data((0..<32).map(UInt8.init))

    static func icon(_ n: Int, source: Data? = nil, label: String = "Icon") -> IconInput {
        IconInput(label: label, dataUrl: "data:image/png;base64,AAAA\(n)", sourceBytes: source)
    }

    // MARK: Blob + crypto

    /// Produced by Node's crypto (what the web client's Web Crypto computes): nonce 100…111, key 0…31,
    /// AAD `pstotp-icon-library-v1`.
    static let nodeBlob = "ZGVmZ2hpamtsbW5vMzmoAwuaP/FQQGXZ9kcDni2sdSixN4hQzrWOctmSlHml2HHxfT+qNczCVQ7Mc/viKmqp1g17cBnLwJ3n3rCUuzmu9yy6Kllg503XYV3lVolGVD1QxrHs5OXTUqUPcnQ44xD1G0Q91hmImL+2xzuMxEt9wlCTVs4Ej1u/k7nGbaZG+vzpHRB4Cft5ZDOksGivpPWpdmBxtqILoU5j0CGVoLIdBTjxqICoCivJ1dZWwqz107D0Srq/nnZYmXev6ygMb68dx0s="

    @Test func decryptsABlobWrittenByTheWebClient() throws {
        let blob = try IconLibraryCrypto.decrypt(vaultKey: Self.key, payload: try #require(Data(base64Encoded: Self.nodeBlob)))
        #expect(blob.version == 1)
        #expect(blob.icons == [LibraryIcon(
            id: "11111111-1111-1111-1111-111111111111", label: "Logo",
            data: "data:image/png;base64,iVBOR/w0=", createdAt: "2026-04-22T00:00:00.000Z", dataHash: "abc")])
    }

    @Test func roundTripsAndUsesAFreshNonce() throws {
        let blob = IconLibraryBlob(icons: [LibraryIcon(id: "a", label: "A", data: "data:x", createdAt: "t", dataHash: "h", sourceHash: "s")])
        let first = try IconLibraryCrypto.encrypt(vaultKey: Self.key, blob: blob)
        let second = try IconLibraryCrypto.encrypt(vaultKey: Self.key, blob: blob)
        #expect(first != second)
        #expect(try IconLibraryCrypto.decrypt(vaultKey: Self.key, payload: first) == blob)
        #expect(throws: (any Error).self) {
            try IconLibraryCrypto.decrypt(vaultKey: Data(repeating: 9, count: 32), payload: first)
        }
    }

    @Test func jsonOmitsMissingHashesAndKeepsSlashesUnescaped() throws {
        let json = try String(decoding: IconLibraryBlob(icons: [
            LibraryIcon(id: "a", label: "A", data: "data:image/png;base64,a/b", createdAt: "t"),
        ]).jsonData(), as: UTF8.self)
        #expect(json.contains("a/b") && !json.contains("\\/"))
        #expect(!json.contains("dataHash") && !json.contains("sourceHash"))
    }

    @Test func readingIsLenient() throws {
        let json = #"{"icons":[{"id":"a","data":"d","label":"","dataHash":""},{"id":"no-data"},"junk"]}"#
        let blob = try IconLibraryBlob(jsonData: Data(json.utf8))
        #expect(blob.version == 1)
        #expect(blob.icons == [LibraryIcon(id: "a", label: "Icon", data: "d", createdAt: "")])
        #expect(throws: IconLibraryError.malformedBlob) { try IconLibraryBlob(jsonData: Data("[]".utf8)) }
    }

    // MARK: Dedup

    private func plan(_ current: [LibraryIcon], _ input: IconInput) -> IconDedup.AddPlan {
        IconDedup.planAdd(current: current, input: input, makeId: { "id" }, now: { "now" })
    }

    @Test func addsThenRecognisesTheSameDataUrlAsDuplicate() throws {
        guard case .added(let one) = plan([], Self.icon(1, label: " ")) else { Issue.record("not added"); return }
        #expect(one.count == 1 && one[0].label == "Icon" && one[0].dataHash != nil && one[0].sourceHash == nil)
        #expect(plan(one, Self.icon(1)) == .duplicate)
        guard case .added(let two) = plan(one, Self.icon(2)) else { Issue.record("not added"); return }
        #expect(two.count == 2)
    }

    @Test func differentResizedIconsFromTheSameSourceAreDuplicates() {
        let source = Data("original".utf8)
        guard case .added(let one) = plan([], Self.icon(1, source: source)) else { Issue.record("not added"); return }
        #expect(plan(one, Self.icon(2, source: source)) == .duplicate)
        #expect(plan(one, Self.icon(2, source: Data("other".utf8))) != .duplicate)
        #expect(plan(one, Self.icon(2)) != .duplicate)          // an absent hash never matches
    }

    @Test func countCapIsEnforced() {
        let full = (0..<IconLibraryLimits.maxIcons).map {
            LibraryIcon(id: "\($0)", label: "L", data: "d\($0)", createdAt: "t", dataHash: "h\($0)")
        }
        #expect(plan(full, Self.icon(1000)) == .countCapExceeded)
    }

    @Test func byteCapIsEnforcedAndCountsEncryptionOverhead() {
        let big = IconInput(label: "Big", dataUrl: "data:" + String(repeating: "x", count: IconLibraryLimits.maxBytes), sourceBytes: nil)
        #expect(plan([], big) == .byteCapExceeded)
        #expect(IconDedup.maxPlaintextBytes == IconLibraryLimits.maxBytes - 28)
    }

    @Test func batchDedupsWithinTheBatchAndCountsOverflow() {
        let existing = LibraryIcon(id: "e", label: "E", data: "data:image/png;base64,AAAA1", createdAt: "t",
                                   dataHash: IconDedup.fingerprint(dataUrl: "data:image/png;base64,AAAA1", sourceBytes: nil).dataHash)
        var counter = 0
        let (icons, result) = IconDedup.planBatch(
            current: [existing], items: [Self.icon(1), Self.icon(2), Self.icon(2), Self.icon(3)],
            makeId: { counter += 1; return "n\(counter)" }, now: { "now" })
        #expect(result == IconBatchResult(added: 2, duplicates: 2, overflow: 0))
        #expect(icons.map(\.id) == ["e", "n1", "n2"])

        let nearlyFull = (0..<(IconLibraryLimits.maxIcons - 1)).map {
            LibraryIcon(id: "\($0)", label: "L", data: "d\($0)", createdAt: "t", dataHash: "h\($0)")
        }
        let capped = IconDedup.planBatch(current: nearlyFull, items: [Self.icon(1), Self.icon(2), Self.icon(3)],
                                         makeId: { "x" }, now: { "now" })
        #expect(capped.result == IconBatchResult(added: 1, duplicates: 0, overflow: 2))
    }

    @Test func backfillsDataHashOnlyWhereMissing() {
        let filled = IconDedup.backfillHashes([
            LibraryIcon(id: "a", label: "A", data: "d", createdAt: "t"),
            LibraryIcon(id: "b", label: "B", data: "d", createdAt: "t", dataHash: "kept"),
        ])
        #expect(filled[0].dataHash == Hash.sha256Hex(Data("d".utf8)))
        #expect(filled[1].dataHash == "kept")
    }

    // MARK: Repository

    @Test func repositoryPersistsEncryptedAndDedups() async throws {
        let db = try AppDatabase.inMemory()
        let repo = IconLibraryRepository(db: db, makeId: { UUID().uuidString.lowercased() }, now: { "2026-01-01T00:00:00.000Z" })
        #expect(try await repo.load(vaultKey: Self.key).isEmpty)

        var icons = try await repo.add(vaultKey: Self.key, current: [], input: Self.icon(1, label: "One"))
        icons = try await repo.add(vaultKey: Self.key, current: icons, input: Self.icon(1, label: "Again"))
        #expect(icons.count == 1)

        let reloaded = try await repo.load(vaultKey: Self.key)
        #expect(reloaded == icons && reloaded[0].label == "One")
        // Stored as ciphertext, and unreadable under another key.
        let stored = try await db.writer.read { try SettingsQueries.get($0, SettingsKeys.iconLibraryCiphertext) }
        #expect(stored?.contains("AAAA1") == false)
        #expect(try await repo.load(vaultKey: Data(repeating: 7, count: 32)).isEmpty)
        #expect(try await db.writer.read { try SettingsQueries.get($0, SettingsKeys.iconLibraryDirty) } == "true")
    }

    @Test func repositoryThrowsWhenFull() async throws {
        let repo = IconLibraryRepository(db: try AppDatabase.inMemory())
        let full = (0..<IconLibraryLimits.maxIcons).map {
            LibraryIcon(id: "\($0)", label: "L", data: "d\($0)", createdAt: "t", dataHash: "h\($0)")
        }
        await #expect(throws: IconLibraryError.countCapExceeded) {
            try await repo.add(vaultKey: Self.key, current: full, input: Self.icon(5000))
        }
    }

    @Test func defaultTimestampLooksLikeToISOString() {
        let stamp = IconLibraryRepository.systemNow()
        #expect(stamp.wholeMatch(of: /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z/) != nil)
    }

    // MARK: Import helpers

    @Test func importLibraryItemsSkipSkippedEmojiAndRepeats() {
        func candidate(_ issuer: String, _ icon: String?, _ action: ImportAction = .addCopy) -> ImportCandidate {
            ImportCandidate(imported: VaultEntryPlaintext(issuer: issuer, accountName: "", secret: "S", icon: icon),
                            existingMatch: nil, action: action)
        }
        let items = ImportIcons.libraryItems([
            candidate("A", "data:image/png;base64,1"), candidate("B", "data:image/png;base64,1"),
            candidate("C", "data:image/png;base64,2", .skip), candidate("D", "🔑"), candidate("E", nil),
            candidate("F", "data:image/png;base64,3"),
        ], sourceBytes: ["data:image/png;base64,3": Data("src".utf8)])
        #expect(items == [
            IconInput(label: "A", dataUrl: "data:image/png;base64,1", sourceBytes: nil),
            IconInput(label: "F", dataUrl: "data:image/png;base64,3", sourceBytes: Data("src".utf8)),
        ])
    }

    @Test func importMessageMatchesAndroid() {
        #expect(ImportIcons.importMessage(entries: 3, icons: nil) == "Imported 3 entries")
        #expect(ImportIcons.importMessage(entries: 3, icons: IconBatchResult()) == "Imported 3 entries")
        #expect(ImportIcons.importMessage(entries: 3, icons: IconBatchResult(added: 1, duplicates: 0, overflow: 0))
                == "Imported 3 entries · 1 icon added")
        #expect(ImportIcons.importMessage(entries: 2, icons: IconBatchResult(added: 2, duplicates: 1, overflow: 3))
                == "Imported 2 entries · 2 icons added (1 duplicate, 3 over limit)")
    }
}
