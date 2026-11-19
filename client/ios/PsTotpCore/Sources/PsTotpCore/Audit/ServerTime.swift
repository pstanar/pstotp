import Foundation

/// The server's ISO 8601 timestamps (.NET writes up to 7 fractional digits, or none) for display.
public enum ServerTime {
    // Format styles are values (and Sendable), so one of each is built once and shared by every row that
    // shows a time, instead of two formatters per call.
    private static let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let withoutFraction = Date.ISO8601FormatStyle()

    /// nil when the text isn't a timestamp.
    public static func date(_ iso: String) -> Date? {
        (try? Date(iso, strategy: withFraction)) ?? (try? Date(iso, strategy: withoutFraction))
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
