import Foundation

/// Presentation of one-time codes.
public enum CodeFormat {
    /// "123456" → "123 456". The first half takes the extra digit for odd lengths ("1234567" →
    /// "1234 567"), as on Android; an empty code stays empty.
    public static func grouped(_ code: String) -> String {
        guard !code.isEmpty else { return "" }
        let mid = (code.count + 1) / 2
        return "\(code.prefix(mid)) \(code.dropFirst(mid))"
    }
}
