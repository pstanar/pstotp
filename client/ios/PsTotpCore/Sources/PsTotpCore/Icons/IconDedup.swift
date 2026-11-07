import Foundation

/// An icon about to be added to the library, before it gets an id.
public struct IconInput: Equatable, Sendable {
    public var label: String
    public var dataUrl: String
    /// The original bytes before resizing (for a stable `sourceHash`), when known.
    public var sourceBytes: Data?

    public init(label: String, dataUrl: String, sourceBytes: Data?) {
        self.label = label
        self.dataUrl = dataUrl
        self.sourceBytes = sourceBytes
    }
}

/// Tally of a batch add, for the import summary.
public struct IconBatchResult: Equatable, Sendable {
    public var added = 0
    public var duplicates = 0
    public var overflow = 0
}

/// Pure content de-duplication and cap logic for the library (Android's `IconDedup`). Two icons are
/// the same if EITHER hash matches; an absent hash never matches.
public enum IconDedup {
    /// AES-GCM adds nonce(12) + tag(16); the server caps the *encrypted* payload.
    static let aeadOverhead = 28
    static let maxPlaintextBytes = IconLibraryLimits.maxBytes - aeadOverhead

    struct Fingerprint {
        let dataHash: String
        let sourceHash: String?
    }

    static func fingerprint(dataUrl: String, sourceBytes: Data?) -> Fingerprint {
        Fingerprint(
            dataHash: Hash.sha256Hex(Data(dataUrl.utf8)),
            sourceHash: sourceBytes.map(Hash.sha256Hex))
    }

    static func findDuplicate(in icons: [LibraryIcon], _ fingerprint: Fingerprint) -> LibraryIcon? {
        icons.first { icon in
            (icon.dataHash != nil && icon.dataHash == fingerprint.dataHash)
                || (icon.sourceHash != nil && fingerprint.sourceHash != nil && icon.sourceHash == fingerprint.sourceHash)
        }
    }

    /// Compute `dataHash` for legacy icons that lack one.
    public static func backfillHashes(_ icons: [LibraryIcon]) -> [LibraryIcon] {
        icons.map { icon in
            guard icon.dataHash == nil else { return icon }
            var copy = icon
            copy.dataHash = Hash.sha256Hex(Data(icon.data.utf8))
            return copy
        }
    }

    static func blobByteLength(_ icons: [LibraryIcon]) -> Int {
        (try? IconLibraryBlob(icons: icons).jsonData().count) ?? .max
    }

    private static func makeIcon(
        _ input: IconInput, _ fingerprint: Fingerprint, id: String, createdAt: String
    ) -> LibraryIcon {
        LibraryIcon(
            id: id,
            label: input.label.isEmpty || input.label.allSatisfy(\.isWhitespace) ? "Icon" : input.label,
            data: input.dataUrl, createdAt: createdAt,
            dataHash: fingerprint.dataHash, sourceHash: fingerprint.sourceHash)
    }

    public enum AddPlan: Equatable {
        /// An existing icon already matches; keep the list as it is.
        case duplicate
        case countCapExceeded
        case byteCapExceeded
        case added([LibraryIcon])
    }

    public static func planAdd(
        current: [LibraryIcon], input: IconInput,
        makeId: () -> String, now: () -> String
    ) -> AddPlan {
        let fingerprint = fingerprint(dataUrl: input.dataUrl, sourceBytes: input.sourceBytes)
        if findDuplicate(in: current, fingerprint) != nil { return .duplicate }
        if current.count >= IconLibraryLimits.maxIcons { return .countCapExceeded }
        let next = current + [makeIcon(input, fingerprint, id: makeId(), createdAt: now())]
        if blobByteLength(next) > maxPlaintextBytes { return .byteCapExceeded }
        return .added(next)
    }

    /// De-dups against `current` and within the batch; skipped icons beyond a cap count as overflow.
    public static func planBatch(
        current: [LibraryIcon], items: [IconInput],
        makeId: () -> String, now: () -> String
    ) -> (icons: [LibraryIcon], result: IconBatchResult) {
        var next = current
        var result = IconBatchResult()
        // Track the JSON size incrementally: one more icon costs its own JSON plus a separator.
        var bytes = blobByteLength(next)
        for item in items {
            let fingerprint = fingerprint(dataUrl: item.dataUrl, sourceBytes: item.sourceBytes)
            if findDuplicate(in: next, fingerprint) != nil {
                result.duplicates += 1
            } else if next.count >= IconLibraryLimits.maxIcons {
                result.overflow += 1
            } else {
                let candidate = makeIcon(item, fingerprint, id: makeId(), createdAt: now())
                let cost = ((try? JSONSerialization.data(
                    withJSONObject: candidate.json, options: [.withoutEscapingSlashes]).count) ?? .max / 2) + 1
                if bytes + cost > maxPlaintextBytes {
                    result.overflow += 1
                } else {
                    next.append(candidate)
                    bytes += cost
                    result.added += 1
                }
            }
        }
        return (next, result)
    }
}
