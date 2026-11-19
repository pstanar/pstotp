import Foundation

/// The server's ISO 8601 timestamps (.NET writes up to 7 fractional digits, or none) for display.
public enum ServerTime {
    /// nil when the text isn't a timestamp.
    public static func date(_ iso: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        return fractional.date(from: iso) ?? plain.date(from: iso)
    }

    /// `Nov 19, 2026`; the first 10 characters of the raw text when unreadable.
    public static func day(_ iso: String, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        guard let date = date(iso) else { return String(iso.prefix(10)) }
        return date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, timeZone: timeZone))
    }

    /// `Nov 19, 2026 at 10:30`; the raw text when unreadable.
    public static func dateTime(_ iso: String, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        guard let date = date(iso) else { return iso }
        return date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, timeZone: timeZone))
    }
}
