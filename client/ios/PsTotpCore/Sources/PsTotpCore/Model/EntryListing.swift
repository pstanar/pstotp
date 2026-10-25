import Foundation

/// Pure sort/filter rules for the vault list (the logic inside Android's `VaultScreen`).
public enum EntryListing {

    /// Entries in display order for `mode`.
    ///
    /// Ties keep their incoming (manual) order, so the result is stable. `reversed` flips the natural
    /// direction of every mode except `.manual`, which is the user's own order.
    public static func sorted(
        _ entries: [VaultEntry],
        mode: SortMode,
        reversed: Bool,
        usage: [String: EntryUsageRecord]
    ) -> [VaultEntry] {
        let natural: [VaultEntry]
        switch mode {
        case .manual:
            natural = entries
        case .alphabetical:
            natural = stableSorted(entries) { a, b in
                let (ai, bi) = (a.issuer.lowercased(), b.issuer.lowercased())
                if ai != bi { return ai < bi }
                let (aa, ba) = (a.accountName.lowercased(), b.accountName.lowercased())
                return aa < ba ? true : (aa == ba ? nil : false)
            }
        case .lru:
            natural = stableSorted(entries) { a, b in
                let (au, bu) = (usage[a.id]?.lastUsedAt ?? 0, usage[b.id]?.lastUsedAt ?? 0)
                return au == bu ? nil : au > bu
            }
        case .mfu:
            natural = stableSorted(entries) { a, b in
                let (ac, bc) = (usage[a.id]?.useCount ?? 0, usage[b.id]?.useCount ?? 0)
                if ac != bc { return ac > bc }
                let (au, bu) = (usage[a.id]?.lastUsedAt ?? 0, usage[b.id]?.lastUsedAt ?? 0)
                return au == bu ? nil : au > bu
            }
        }
        return (reversed && mode != .manual) ? natural.reversed() : natural
    }

    /// Case-insensitive substring match on issuer or account name; a blank query matches all.
    public static func filtered(_ entries: [VaultEntry], query: String) -> [VaultEntry] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return entries }
        let q = query.lowercased()
        return entries.filter {
            $0.issuer.lowercased().contains(q) || $0.accountName.lowercased().contains(q)
        }
    }

    /// `areInOrder` returns true/false when the pair is ordered, nil when they tie.
    private static func stableSorted(
        _ entries: [VaultEntry], by areInOrder: (VaultEntry, VaultEntry) -> Bool?
    ) -> [VaultEntry] {
        entries.enumerated().sorted { l, r in
            areInOrder(l.element, r.element) ?? (l.offset < r.offset)
        }.map(\.element)
    }
}
