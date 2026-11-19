import Foundation

/// How the Audit Log shows an event (Android's `AuditScreen` helpers).
public enum AuditFormat {
    /// `LoginSuccess` → `Login Success`, `DeviceApproved` → `Device Approved`.
    public static func title(_ eventType: String) -> String {
        var result = ""
        var previous: Character?
        for character in eventType {
            if let previous, previous.isLowercase, character.isUppercase { result.append(" ") }
            result.append(character)
            previous = character
        }
        return result
    }

    /// The server's ISO 8601 time (any number of fractional digits) as a date; nil when unreadable.
    public static func date(_ iso: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        return fractional.date(from: iso) ?? plain.date(from: iso)
    }

    /// `Nov 19, 12:30` in the user's time zone and locale; the first 16 characters of the raw text
    /// when it can't be read, like Android.
    public static func timestamp(_ iso: String, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        guard let date = date(iso) else { return String(iso.prefix(16)) }
        var style = Date.FormatStyle(locale: locale, timeZone: timeZone)
        style = style.month(.abbreviated).day().hour().minute()
        return date.formatted(style)
    }
}
