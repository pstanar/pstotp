import Foundation

/// Action to take for a duplicate entry during import.
public enum ImportAction: Sendable {
    /// Overwrite the existing entry with imported data.
    case overwrite
    /// Add as a new entry with a deduplicated name.
    case addCopy
    /// Skip this entry entirely.
    case skip
}

/// An imported entry paired with its conflict-resolution state.
public struct ImportCandidate: Equatable, Sendable {
    public var imported: VaultEntryPlaintext
    public var existingMatch: VaultEntry?
    public var action: ImportAction

    public var isDuplicate: Bool { existingMatch != nil }

    public init(imported: VaultEntryPlaintext, existingMatch: VaultEntry?, action: ImportAction) {
        self.imported = imported
        self.existingMatch = existingMatch
        self.action = action
    }

    /// Match imported entries against the vault on issuer + accountName (case-insensitive).
    public static func buildCandidates(imported: [VaultEntryPlaintext], existing: [VaultEntry]) -> [ImportCandidate] {
        imported.map { entry in
            let match = existing.first {
                $0.issuer.caseInsensitiveCompare(entry.issuer) == .orderedSame
                    && $0.accountName.caseInsensitiveCompare(entry.accountName) == .orderedSame
            }
            return ImportCandidate(imported: entry, existingMatch: match, action: match != nil ? .overwrite : .addCopy)
        }
    }

    /// A unique account name for `issuer`, appending (2), (3), … when taken.
    public static func makeUniqueName(_ name: String, issuer: String, existing: [VaultEntry]) -> String {
        let taken = Set(
            existing
                .filter { $0.issuer.caseInsensitiveCompare(issuer) == .orderedSame }
                .map { $0.accountName.lowercased() }
        )
        if !taken.contains(name.lowercased()) { return name }
        var i = 2
        while taken.contains("\(name) (\(i))".lowercased()) { i += 1 }
        return "\(name) (\(i))"
    }
}
