import Foundation

public enum SortMode: String, CaseIterable, Sendable {
    case manual, alphabetical, lru, mfu

    public var storageKey: String { rawValue }

    public var label: String {
        switch self {
        case .manual: "Manual"
        case .alphabetical: "Alphabetical"
        case .lru: "Recently used"
        case .mfu: "Most used"
        }
    }

    public static func fromStorageKey(_ key: String?) -> SortMode {
        key.flatMap(SortMode.init(rawValue:)) ?? .manual
    }
}

public enum LayoutMode: String, CaseIterable, Sendable {
    case list, grid

    public var storageKey: String { rawValue }

    public var label: String {
        switch self {
        case .list: "List"
        case .grid: "Grid"
        }
    }

    public static func fromStorageKey(_ key: String?) -> LayoutMode {
        key.flatMap(LayoutMode.init(rawValue:)) ?? .list
    }
}

/// Preset durations for auto-lock after backgrounding. `never` uses `Int64.max`
/// so a `duration > timeout` check never fires; no special case needed elsewhere.
public enum LockTimeout: CaseIterable, Sendable {
    case oneMinute, fiveMinutes, fifteenMinutes, oneHour, never

    public var millis: Int64 {
        switch self {
        case .oneMinute: 60_000
        case .fiveMinutes: 5 * 60_000
        case .fifteenMinutes: 15 * 60_000
        case .oneHour: 60 * 60_000
        case .never: Int64.max
        }
    }

    public var label: String {
        switch self {
        case .oneMinute: "1 minute"
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        case .oneHour: "1 hour"
        case .never: "Never"
        }
    }

    /// Nearest preset to a persisted value; falls back to the default.
    public static func fromMillis(_ ms: Int64?, default fallback: LockTimeout = .fiveMinutes) -> LockTimeout {
        guard let ms else { return fallback }
        return allCases.first { $0.millis == ms } ?? fallback
    }
}
