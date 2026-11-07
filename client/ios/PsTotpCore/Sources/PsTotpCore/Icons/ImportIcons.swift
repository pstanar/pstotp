import Foundation

/// Resolves the icons of imported entries before they are shown for confirmation, as Android's
/// `VaultViewModel.resolveIcons` does: URL icons are downloaded, embedded `data:` icons (Aegis,
/// 2FAS) decoded, and both normalised to a 64×64 PNG. Icons that can't be resolved are dropped;
/// emoji icons are kept as they are.
public enum ImportIcons {
    /// Downloads an icon's bytes; nil on any failure.
    public typealias Fetch = @Sendable (URL) async -> Data?

    public static func needsResolving(_ icon: String?) -> Bool {
        IconNormalizer.isUrl(icon) || (icon?.hasPrefix("data:") ?? false)
    }

    /// The number of distinct icons `resolve` will work on (for a progress indicator).
    public static func pendingCount(_ entries: [VaultEntryPlaintext]) -> Int {
        Set(entries.compactMap(\.icon).filter(needsResolving)).count
    }

    /// The resolved entries, and the original (pre-resize) bytes of each resolved icon keyed by its
    /// normalised data URL, which the library uses for a stable `sourceHash`.
    public struct Resolved: Sendable {
        public var entries: [VaultEntryPlaintext]
        public var sourceBytes: [String: Data]
    }

    /// - Parameter progress: called with (done, total) after each distinct icon.
    public static func resolve(
        _ entries: [VaultEntryPlaintext],
        fetch: Fetch,
        progress: @Sendable (Int, Int) async -> Void = { _, _ in }
    ) async -> Resolved {
        var originals = [String]()
        for icon in entries.compactMap(\.icon) where needsResolving(icon) && !originals.contains(icon) {
            originals.append(icon)
        }
        guard !originals.isEmpty else { return Resolved(entries: entries, sourceBytes: [:]) }

        var resolved = [String: String]()
        var sources = [String: Data]()
        for (index, original) in originals.enumerated() {
            if let (dataUrl, bytes) = await resolveOne(original, fetch: fetch) {
                resolved[original] = dataUrl
                sources[dataUrl] = bytes
            }
            await progress(index + 1, originals.count)
        }
        let mapped = entries.map { entry in
            guard let icon = entry.icon, needsResolving(icon) else { return entry }
            var copy = entry
            copy.icon = resolved[icon]
            return copy
        }
        return Resolved(entries: mapped, sourceBytes: sources)
    }

    private static func resolveOne(_ original: String, fetch: Fetch) async -> (String, Data)? {
        var bytes: Data?
        if IconNormalizer.isUrl(original) {
            if let url = URL(string: original) { bytes = await fetch(url) }
        } else {
            bytes = IconNormalizer.dataUrlBytes(original)
        }
        guard let bytes, let dataUrl = IconNormalizer.normalizedDataUrl(imageBytes: bytes) else { return nil }
        return (dataUrl, bytes)
    }

    /// The icons of a confirmed import to add to the library: embedded images of candidates that
    /// aren't skipped, each distinct icon once, labelled with the issuer (Android's
    /// `maybeAddImportedIconsToLibrary`).
    public static func libraryItems(
        _ candidates: [ImportCandidate], sourceBytes: [String: Data]
    ) -> [IconInput] {
        var seen = Set<String>()
        var items = [IconInput]()
        for candidate in candidates where candidate.action != .skip {
            guard let icon = candidate.imported.icon, icon.hasPrefix("data:"), seen.insert(icon).inserted else { continue }
            items.append(IconInput(label: candidate.imported.issuer, dataUrl: icon, sourceBytes: sourceBytes[icon]))
        }
        return items
    }

    /// Toast text for a finished import, with the icon tally when icons were added.
    public static func importMessage(entries: Int, icons: IconBatchResult?) -> String {
        var message = "Imported \(entries) entries"
        guard let icons, icons.added > 0 || icons.duplicates > 0 || icons.overflow > 0 else { return message }
        message += " · \(icons.added) icon\(icons.added == 1 ? "" : "s") added"
        var extra = [String]()
        if icons.duplicates > 0 { extra.append("\(icons.duplicates) duplicate\(icons.duplicates == 1 ? "" : "s")") }
        if icons.overflow > 0 { extra.append("\(icons.overflow) over limit") }
        if !extra.isEmpty { message += " (\(extra.joined(separator: ", ")))" }
        return message
    }
}
