import Foundation
import Testing
@testable import PsTotpCore

@Suite("App logic: listing, auto-lock, validation")
struct AppLogicTests {

    private func entry(_ id: String, _ issuer: String, _ account: String = "me") -> VaultEntry {
        VaultEntry(id: id, issuer: issuer, accountName: account, secret: "JBSWY3DPEHPK3PXP")
    }

    private func ids(_ entries: [VaultEntry]) -> [String] { entries.map(\.id) }

    private var sample: [VaultEntry] {
        [entry("1", "Zeta"), entry("2", "alpha", "b"), entry("3", "Alpha", "A"), entry("4", "Mid")]
    }

    // MARK: Sorting

    @Test func manualKeepsOrderAndIgnoresReversal() {
        #expect(ids(EntryListing.sorted(sample, mode: .manual, reversed: false, usage: [:])) == ["1", "2", "3", "4"])
        #expect(ids(EntryListing.sorted(sample, mode: .manual, reversed: true, usage: [:])) == ["1", "2", "3", "4"])
    }

    @Test func alphabeticalIsCaseInsensitiveByIssuerThenAccount() {
        let sorted = EntryListing.sorted(sample, mode: .alphabetical, reversed: false, usage: [:])
        #expect(ids(sorted) == ["3", "2", "4", "1"])     // Alpha/A, alpha/b, Mid, Zeta
        #expect(ids(EntryListing.sorted(sample, mode: .alphabetical, reversed: true, usage: [:])) == ["1", "4", "2", "3"])
    }

    @Test func alphabeticalTiesKeepManualOrder() {
        let twins = [entry("a", "Same", "x"), entry("b", "Same", "x"), entry("c", "Same", "x")]
        #expect(ids(EntryListing.sorted(twins, mode: .alphabetical, reversed: false, usage: [:])) == ["a", "b", "c"])
    }

    @Test func lruOrdersByMostRecentUseUnusedLastInManualOrder() {
        let usage = [
            "2": EntryUsageRecord(entryId: "2", lastUsedAt: 100, useCount: 1),
            "4": EntryUsageRecord(entryId: "4", lastUsedAt: 300, useCount: 1),
        ]
        #expect(ids(EntryListing.sorted(sample, mode: .lru, reversed: false, usage: usage)) == ["4", "2", "1", "3"])
    }

    @Test func mfuOrdersByCountThenRecency() {
        let usage = [
            "1": EntryUsageRecord(entryId: "1", lastUsedAt: 10, useCount: 5),
            "2": EntryUsageRecord(entryId: "2", lastUsedAt: 50, useCount: 5),
            "3": EntryUsageRecord(entryId: "3", lastUsedAt: 99, useCount: 2),
        ]
        #expect(ids(EntryListing.sorted(sample, mode: .mfu, reversed: false, usage: usage)) == ["2", "1", "3", "4"])
        #expect(ids(EntryListing.sorted(sample, mode: .mfu, reversed: true, usage: usage)) == ["4", "3", "1", "2"])
    }

    // MARK: Filtering

    @Test func filterMatchesIssuerOrAccountCaseInsensitively() {
        let list = [entry("1", "GitHub", "octocat"), entry("2", "Google", "alice@example.com"), entry("3", "AWS", "root")]
        #expect(ids(EntryListing.filtered(list, query: "git")) == ["1"])
        #expect(ids(EntryListing.filtered(list, query: "EXAMPLE")) == ["2"])
        #expect(ids(EntryListing.filtered(list, query: "o")) == ["1", "2", "3"])
        #expect(EntryListing.filtered(list, query: "zzz").isEmpty)
    }

    @Test func blankQueryMatchesEverything() {
        #expect(EntryListing.filtered(sample, query: "").count == 4)
        #expect(EntryListing.filtered(sample, query: "   ").count == 4)
    }

    // MARK: Auto-lock

    @Test func autoLockFiresOnlyAfterTheTimeout() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        func lock(_ secs: Double, _ timeout: LockTimeout) -> Bool {
            AutoLock.shouldLock(backgroundedAt: t0, now: t0.addingTimeInterval(secs), timeout: timeout)
        }
        #expect(!lock(59, .oneMinute))
        #expect(!lock(60, .oneMinute))        // strictly greater, like Android
        #expect(lock(60.5, .oneMinute))
        #expect(lock(301, .fiveMinutes))
        #expect(!lock(299, .fiveMinutes))
        #expect(!lock(10_000_000, .never))
    }

    @Test func autoLockIgnoresUnknownBackgroundTimeAndClockGoingBackwards() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(!AutoLock.shouldLock(backgroundedAt: nil, now: now, timeout: .oneMinute))
        #expect(!AutoLock.shouldLock(backgroundedAt: now.addingTimeInterval(500), now: now, timeout: .oneMinute))
    }

    // MARK: Validation

    @Test func manualEntryNormalisesAndDefaults() throws {
        let e = try EntryValidation.manualEntry(
            issuer: "  ", accountName: " bob ", secret: " jbsw y3dp ehpk 3pxp ",
            algorithm: "SHA256", digits: "8", period: "60", icon: "🔑")
        #expect(e == VaultEntryPlaintext(issuer: "Unknown", accountName: "bob", secret: "JBSWY3DPEHPK3PXP",
                                         algorithm: "SHA256", digits: 8, period: 60, icon: "🔑"))
    }

    @Test func manualEntryRejectsBadInput() {
        func make(secret: String = "JBSWY3DPEHPK3PXP", digits: String = "6", period: String = "30") throws {
            _ = try EntryValidation.manualEntry(issuer: "I", accountName: "A", secret: secret,
                                                algorithm: "SHA1", digits: digits, period: period)
        }
        #expect(throws: EntryValidationError.secretRequired) { try make(secret: "   ") }
        #expect(throws: EntryValidationError.secretInvalid) { try make(secret: "not base32 !!") }
        #expect(throws: EntryValidationError.secretInvalid) { try make(secret: "A") }      // decodes to zero bytes
        #expect(throws: EntryValidationError.digitsOutOfRange) { try make(digits: "3") }
        #expect(throws: EntryValidationError.digitsOutOfRange) { try make(digits: "abc") }
        #expect(throws: EntryValidationError.periodInvalid) { try make(period: "0") }
        #expect(throws: EntryValidationError.periodInvalid) { try make(period: "x") }
    }

    @Test func emptySecretIsReportedBeforeOtherFieldErrors() {
        #expect(throws: EntryValidationError.secretRequired) {
            _ = try EntryValidation.manualEntry(issuer: "I", accountName: "A", secret: "",
                                                algorithm: "SHA1", digits: "x", period: "y")
        }
    }

    @Test func validatedChecksParsedUriEntries() throws {
        let ok = try EntryValidation.validated(try OtpauthUri.parse("otpauth://totp/a?secret=jbsw%20y3dp"))
        #expect(ok.secret == "JBSWY3DP")
        #expect(throws: EntryValidationError.secretInvalid) {
            _ = try EntryValidation.validated(try OtpauthUri.parse("otpauth://totp/a?secret=!!!!"))
        }
    }

    @Test func everyValidatedSecretProducesATotpCode() throws {
        let e = try EntryValidation.manualEntry(issuer: "I", accountName: "A", secret: "jbswy3dpehpk3pxp",
                                                algorithm: "SHA1", digits: "6", period: "30")
        let code = try TotpGenerator.generate(secret: e.secret, algorithm: e.algorithm, digits: e.digits,
                                              period: e.period, timestampSeconds: 1234567890)
        #expect(code == "742275")          // same pinned value as the Kotlin test
    }
}

@Suite("Grid selection and code formatting")
struct GridSupportTests {
    @Test func selectionKeepsAVisibleEntryAndFallsBackToTheFirst() {
        #expect(EntryListing.selection(current: "b", in: ["a", "b", "c"]) == "b")
        #expect(EntryListing.selection(current: "z", in: ["a", "b", "c"]) == "a")     // filtered out → first
        #expect(EntryListing.selection(current: nil, in: ["a", "b"]) == "a")
        #expect(EntryListing.selection(current: "a", in: []) == nil)
        #expect(EntryListing.selection(current: nil, in: []) == nil)
    }

    @Test func codesGroupIntoTwoHalves() {
        #expect(CodeFormat.grouped("123456") == "123 456")
        #expect(CodeFormat.grouped("12345678") == "1234 5678")
        #expect(CodeFormat.grouped("1234567") == "1234 567")
        #expect(CodeFormat.grouped("12345") == "123 45")
        #expect(CodeFormat.grouped("1") == "1 ")
        #expect(CodeFormat.grouped("") == "")
    }

    @Test func layoutModeStorageKeysAndLabels() {
        #expect(LayoutMode.fromStorageKey("grid") == .grid)
        #expect(LayoutMode.fromStorageKey("list") == .list)
        #expect(LayoutMode.fromStorageKey("nonsense") == .list)
        #expect(LayoutMode.fromStorageKey(nil) == .list)
        #expect(LayoutMode.grid.storageKey == "grid" && LayoutMode.list.storageKey == "list")
    }
}

@Suite("PasswordPolicy")
struct PasswordPolicyTests {
    @Test func reportsTheFirstViolatedRule() {
        #expect(PasswordPolicy.validate("Ab1!", confirm: "Ab1!") == "Password must be at least 8 characters")
        #expect(PasswordPolicy.validate("abcdefg1!", confirm: "abcdefg1!") == "Must contain an uppercase letter")
        #expect(PasswordPolicy.validate("ABCDEFG1!", confirm: "ABCDEFG1!") == "Must contain a lowercase letter")
        #expect(PasswordPolicy.validate("Abcdefgh!", confirm: "Abcdefgh!") == "Must contain a number")
        #expect(PasswordPolicy.validate("Abcdefg12", confirm: "Abcdefg12") == "Must contain a special character")
        #expect(PasswordPolicy.validate("Abcdef1!", confirm: "Abcdef1?") == "Passwords do not match")
    }

    @Test func acceptsAStrongPasswordIncludingUnicodeAndSpaces() {
        #expect(PasswordPolicy.validate("Abcdef1!", confirm: "Abcdef1!") == nil)
        #expect(PasswordPolicy.validate("Pässwörd 1", confirm: "Pässwörd 1") == nil)   // space counts as special
        #expect(PasswordPolicy.validate("Ünïcode1🔑", confirm: "Ünïcode1🔑") == nil)
    }

    @Test func lengthCountsCharactersNotBytes() {
        #expect(PasswordPolicy.validate("Aa1!éééé", confirm: "Aa1!éééé") == nil)        // 8 characters
    }
}
