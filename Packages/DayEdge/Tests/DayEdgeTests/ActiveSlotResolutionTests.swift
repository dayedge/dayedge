import XCTest
@testable import Shell

final class ActiveSlotResolutionTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: hour, minute: minute))!
    }

    func testNoCandidatesReturnsNil() {
        let result = resolveActiveSlot([ActiveSlotCandidate<String>](), now: date(10), leadMinutes: 15)
        XCTAssertNil(result)
    }

    func testSingleCandidateWindowBoundaries() {
        let candidate = ActiveSlotCandidate(value: "A", start: date(10), end: date(11))

        XCTAssertNil(resolveActiveSlot([candidate], now: date(9, 44), leadMinutes: 15), "just before the lead window")
        XCTAssertEqual(resolveActiveSlot([candidate], now: date(9, 45), leadMinutes: 15), "A", "exactly at the lead window's start")
        XCTAssertEqual(resolveActiveSlot([candidate], now: date(10, 59), leadMinutes: 15), "A", "just before the event ends")
        XCTAssertNil(resolveActiveSlot([candidate], now: date(11), leadMinutes: 15), "exactly at the event's own end")
    }

    func testTwoCandidatesHandOffAtNextStart() {
        let first = ActiveSlotCandidate(value: "A", start: date(10), end: date(11))
        let second = ActiveSlotCandidate(value: "B", start: date(10, 30), end: date(11, 30))

        XCTAssertEqual(resolveActiveSlot([first, second], now: date(10, 20), leadMinutes: 15), "A", "before B's start — A still current")
        XCTAssertEqual(resolveActiveSlot([first, second], now: date(10, 30), leadMinutes: 15), "B", "B's own start — hands off even though A hasn't ended")
        XCTAssertNil(resolveActiveSlot([first, second], now: date(9, 44), leadMinutes: 15), "before either's lead window")
    }

    func testCandidateOrderInArrayDoesNotMatter() {
        let first = ActiveSlotCandidate(value: "A", start: date(10), end: date(11))
        let second = ActiveSlotCandidate(value: "B", start: date(10, 30), end: date(11, 30))

        XCTAssertEqual(resolveActiveSlot([second, first], now: date(10, 20), leadMinutes: 15), "A")
    }
}
