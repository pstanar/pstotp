import Foundation

/// Action to take for a duplicate entry during import.
public enum ImportAction: CaseIterable, Sendable {
    /// Overwrite the existing entry with imported data.
    case overwrite
    /// Add as a new entry with a deduplicated name.
    case addCopy
    /// Skip this entry entirely.
    case skip

    public var label: String {
        switch self {
        case .overwrite: "Overwrite"
        case .addCopy: "Add copy"
        case .skip: "Skip"
        }
    }
}

/// What a confirmed import writes: existing entries to overwrite and new entries to add, in
/// candidate order.
public struct ImportPlan: Equatable, Sendable {
    public var updates: [VaultEntry]
    public var additions: [VaultEntryPlaintext]

    public var count: Int { updates.count + additions.count }
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

    /// Set `action` on every duplicate; non-duplicates keep theirs.
    public static func settingDuplicateAction(_ action: ImportAction, in candidates: [ImportCandidate]) -> [ImportCandidate] {
        candidates.map { candidate in
            var c = candidate
            if c.isDuplicate { c.action = action }
            return c
        }
    }

    /// Turn the user's choices into writes, as Android's `confirmImport` does: skips are dropped,
    /// an overwrite replaces the matched entry's fields (keeping its id, version and position), and
    /// anything else is added — a duplicate under a unique name that also avoids names added
    /// earlier in the same import.
    public static func plan(_ candidates: [ImportCandidate], existing: [VaultEntry]) -> ImportPlan {
        var plan = ImportPlan(updates: [], additions: [])
        var taken = existing   // grows with each addition, for name de-duplication
        for candidate in candidates where candidate.action != .skip {
            let imported = candidate.imported
            if candidate.action == .overwrite, let match = candidate.existingMatch {
                var updated = match
                updated.issuer = imported.issuer
                updated.accountName = imported.accountName
                updated.secret = imported.secret
                updated.algorithm = imported.algorithm
                updated.digits = imported.digits
                updated.period = imported.period
                updated.icon = imported.icon
                plan.updates.append(updated)
            } else {
                var addition = imported
                if candidate.existingMatch != nil {
                    addition.accountName = makeUniqueName(imported.accountName, issuer: imported.issuer, existing: taken)
                }
                plan.additions.append(addition)
                taken.append(VaultEntry(id: "", plaintext: addition))
            }
        }
        return plan
    }
}
