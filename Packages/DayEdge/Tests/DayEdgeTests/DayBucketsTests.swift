import XCTest
@testable import Shell
@testable import Platform

final class DayBucketsTests: XCTestCase {
    private struct FakeSpan: EventSpanning, Equatable {
        let rawID: String
        let startDate: Date
        let endDate: Date
        var id: AnyHashable { rawID }
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour))!
    }

    private func buckets(_ items: [FakeSpan], from start: Int, to end: Int) -> [Date: [FakeSpan]] {
        DayBuckets.index(items, calendar: calendar, windowStart: date(start), windowEnd: date(end), mergingInto: [:])
    }

    func testSameDayItemAppearsOnlyOnItsOwnDay() {
        let item = FakeSpan(rawID: "A", startDate: date(10, 9), endDate: date(10, 10))
        let result = buckets([item], from: 10, to: 11)
        XCTAssertEqual(result[date(10)], [item])
        XCTAssertNil(result[date(9)])
        XCTAssertNil(result[date(11)])
    }

    func testThreeDaySpanAppearsOnAllThreeDays() {
        // Ends exactly at day 13's midnight — an exclusive boundary, so day
        // 13 itself isn't spanned.
        let item = FakeSpan(rawID: "A", startDate: date(10, 22), endDate: date(13))
        let result = buckets([item], from: 9, to: 14)
        XCTAssertEqual(result[date(10)], [item])
        XCTAssertEqual(result[date(11)], [item])
        XCTAssertEqual(result[date(12)], [item])
        XCTAssertNil(result[date(13)])
    }

    func testTimedEventCrossingMidnightAppearsOnBothDays() {
        let item = FakeSpan(rawID: "A", startDate: date(10, 22), endDate: date(11, 2))
        let result = buckets([item], from: 9, to: 12)
        XCTAssertEqual(result[date(10)], [item])
        XCTAssertEqual(result[date(11)], [item])
    }

    func testAllDayEventExclusiveEndDateDoesNotLeakAnExtraDay() {
        // EventKit's convention for a 2-day all-day event: start at day
        // 10's midnight, end at day 12's midnight (exclusive).
        let item = FakeSpan(rawID: "A", startDate: date(10), endDate: date(12))
        let result = buckets([item], from: 9, to: 13)
        XCTAssertEqual(result[date(10)], [item])
        XCTAssertEqual(result[date(11)], [item])
        XCTAssertNil(result[date(12)], "day 12 is the exclusive end bound, not a day the event actually occupies")
    }

    func testSpanExtendingPastTheWindowIsClamped() {
        let item = FakeSpan(rawID: "A", startDate: date(1), endDate: date(30))
        let result = buckets([item], from: 10, to: 12)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[date(10)], [item])
        XCTAssertEqual(result[date(11)], [item])
        XCTAssertEqual(result[date(12)], [item])
    }

    func testItemListedTwiceIsPlacedOnce() {
        let item = FakeSpan(rawID: "A", startDate: date(10, 9), endDate: date(11, 9))
        let result = buckets([item, item], from: 9, to: 12)
        XCTAssertEqual(result[date(10)], [item])
        XCTAssertEqual(result[date(11)], [item])
    }
}
