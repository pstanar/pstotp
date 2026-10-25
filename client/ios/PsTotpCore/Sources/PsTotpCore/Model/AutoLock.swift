import Foundation

/// Auto-lock decision after the app returns from the background.
public enum AutoLock {
    /// True when the app was backgrounded for longer than `timeout` (strictly, as on Android).
    /// `LockTimeout.never` uses `Int64.max`, so it never fires.
    public static func shouldLock(backgroundedAt: Date?, now: Date, timeout: LockTimeout) -> Bool {
        guard let backgroundedAt else { return false }
        let elapsedMs = Int64(max(0, now.timeIntervalSince(backgroundedAt)) * 1000)
        return elapsedMs > timeout.millis
    }
}
