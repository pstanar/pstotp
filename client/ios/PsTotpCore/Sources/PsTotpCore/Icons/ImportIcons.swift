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

    /// - Parameter progress: called with (done, total) after each distinct icon.
    public static func resolve(
        _ entries: [VaultEntryPlaintext],
        fetch: Fetch,
        progress: @Sendable (Int, Int) async -> Void = { _, _ in }
    ) async -> [VaultEntryPlaintext] {
        var originals = [String]()
        for icon in entries.compactMap(\.icon) where needsResolving(icon) && !originals.contains(icon) {
            originals.append(icon)
        }
        guard !originals.isEmpty else { return entries }

        var resolved = [String: String]()
        for (index, original) in originals.enumerated() {
            resolved[original] = await resolveOne(original, fetch: fetch)
            await progress(index + 1, originals.count)
        }
        return entries.map { entry in
            guard let icon = entry.icon, needsResolving(icon) else { return entry }
            var copy = entry
            copy.icon = resolved[icon]
            return copy
        }
    }

    private static func resolveOne(_ original: String, fetch: Fetch) async -> String? {
        var bytes: Data?
        if IconNormalizer.isUrl(original) {
            if let url = URL(string: original) { bytes = await fetch(url) }
        } else {
            bytes = IconNormalizer.dataUrlBytes(original)
        }
        return bytes.flatMap(IconNormalizer.normalizedDataUrl(imageBytes:))
    }
}
