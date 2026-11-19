import Foundation
import Testing
@testable import PsTotpCore

@Suite("AuditFormat")
struct AuditFormatTests {
    @Test func splitsPascalCaseEventTypes() {
        #expect(AuditFormat.title("LoginSuccess") == "Login Success")
        #expect(AuditFormat.title("DeviceApproved") == "Device Approved")
        #expect(AuditFormat.title("PasswordChanged") == "Password Changed")
        #expect(AuditFormat.title("Login") == "Login")
        #expect(AuditFormat.title("") == "")
        #expect(AuditFormat.title("TOTPVaultExported") == "TOTPVault Exported")   // Android's regex does the same
    }

    @Test func readsTheServersTimestamps() throws {
        // .NET writes up to 7 fractional digits; sometimes none.
        for iso in ["2026-11-19T10:30:00Z", "2026-11-19T10:30:00.1234567Z", "2026-11-19T10:30:00.5Z"] {
            let date = try #require(AuditFormat.date(iso), "\(iso)")
            #expect(Int(date.timeIntervalSince1970) == 1_795_084_200)
        }
        #expect(AuditFormat.date("yesterday") == nil)
    }

    @Test func showsTheTimeInTheGivenZone() {
        let us = Locale(identifier: "en_US")
        let utc = AuditFormat.timestamp("2026-11-19T10:30:00Z", timeZone: TimeZone(identifier: "UTC")!, locale: us)
        let tokyo = AuditFormat.timestamp("2026-11-19T10:30:00Z", timeZone: TimeZone(identifier: "Asia/Tokyo")!, locale: us)
        #expect(utc.contains("Nov 19") && utc.contains("10:30"))
        #expect(tokyo.contains("Nov 19") && tokyo.contains("7:30"))   // 19:30 in en_US is "7:30 PM"
        #expect(tokyo.contains("PM"))
    }

    @Test func unreadableTimesFallBackToTheRawStart() {
        #expect(AuditFormat.timestamp("not a timestamp at all, really") == "not a timestamp ")
        #expect(AuditFormat.timestamp("short") == "short")
    }
}

@Suite("ServerTime")
struct ServerTimeTests {
    private let us = Locale(identifier: "en_US")
    private let utc = TimeZone(identifier: "UTC")!

    @Test func showsTheDayAndTheTime() {
        #expect(ServerTime.day("2026-11-19T23:30:00.1234567Z", timeZone: utc, locale: us) == "Nov 19, 2026")
        #expect(ServerTime.day("2026-11-19T23:30:00Z", timeZone: TimeZone(identifier: "Asia/Tokyo")!, locale: us) == "Nov 20, 2026")
        let both = ServerTime.dateTime("2026-11-19T10:30:00Z", timeZone: utc, locale: us)
        #expect(both.contains("Nov 19, 2026") && both.contains("10:30"))
    }

    @Test func unreadableTextFallsBack() {
        #expect(ServerTime.day("2026-11-19 garbage") == "2026-11-19")
        #expect(ServerTime.dateTime("garbage") == "garbage")
        #expect(ServerTime.date("") == nil)
    }
}
