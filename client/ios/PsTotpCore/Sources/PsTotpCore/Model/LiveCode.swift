import Foundation

/// An entry's codes at one instant, with the "show upcoming code" rules shared by the list card and
/// the grid detail (Android's `TotpCard` / `TotpGridDetail`): in the last 10 s the next code is
/// previewed, and a copy in the last 3 s hands out the next code so it doesn't expire mid-paste.
public struct LiveCode: Equatable, Sendable {
    public static let previewSeconds = 10
    public static let copyNextSeconds = 3

    /// Nil when the entry can't produce codes.
    public let code: String?
    public let nextCode: String?
    public let timeLeft: Int

    public init(entry: VaultEntry, now: Int64) {
        code = entry.code(at: now)
        nextCode = entry.code(at: now + Int64(entry.period))
        timeLeft = TotpGenerator.timeRemaining(period: entry.period, now: now)
    }

    /// The code to preview under the current one, if any.
    public func preview(enabled: Bool) -> String? {
        enabled && timeLeft <= Self.previewSeconds ? nextCode : nil
    }

    /// What a copy hands out right now.
    public func toCopy(showNextCode: Bool) -> (code: String, isNext: Bool)? {
        if showNextCode, timeLeft <= Self.copyNextSeconds, let nextCode { return (nextCode, true) }
        return code.map { ($0, false) }
    }
}
