import Testing
@testable import PsTotpCore

@Suite("Live code & next-code preview")
struct LiveCodeTests {
    let entry = VaultEntry(id: "a", issuer: "I", accountName: "A", secret: "JBSWY3DPEHPK3PXP")

    /// A timestamp `left` seconds before the end of a 30 s step.
    private func at(left: Int) -> Int64 { 59_999_970 + Int64(30 - left) }

    @Test func nextCodeIsTheFollowingStepsCode() {
        let live = LiveCode(entry: entry, now: at(left: 30))
        #expect(live.timeLeft == 30)
        #expect(live.code == entry.code(at: at(left: 30)))
        #expect(live.nextCode == entry.code(at: at(left: 30) + 30))
        #expect(live.code != live.nextCode)
    }

    @Test func previewOnlyInTheLastTenSecondsAndOnlyWhenEnabled() {
        #expect(LiveCode(entry: entry, now: at(left: 11)).preview(enabled: true) == nil)
        let ten = LiveCode(entry: entry, now: at(left: 10))
        #expect(ten.preview(enabled: true) == ten.nextCode)
        #expect(ten.preview(enabled: false) == nil)
    }

    @Test func copyHandsOutTheNextCodeOnlyInTheLastThreeSeconds() throws {
        let four = LiveCode(entry: entry, now: at(left: 4))
        #expect(try #require(four.toCopy(showNextCode: true)) == (four.code!, false))
        let three = LiveCode(entry: entry, now: at(left: 3))
        #expect(try #require(three.toCopy(showNextCode: true)) == (three.nextCode!, true))
        #expect(try #require(three.toCopy(showNextCode: false)) == (three.code!, false))
    }

    @Test func anEntryThatCantProduceCodesHasNothingToShowOrCopy() {
        let bad = VaultEntry(id: "b", issuer: "I", accountName: "A", secret: "not base32!")
        let live = LiveCode(entry: bad, now: at(left: 2))
        #expect(live.code == nil && live.nextCode == nil)
        #expect(live.preview(enabled: true) == nil)
        #expect(live.toCopy(showNextCode: true) == nil)
    }
}
