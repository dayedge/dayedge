import XCTest
@testable import Shell
@testable import Domain
@testable import Agenda

final class DayTimelineSegmentLabelTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private func day(_ day: Int) -> Date {
        date(day, 0)
    }

    private func event(start: Date, end: Date, startTime: String = "15:45", endTime: String = "16:45") -> AgendaEventModel {
        AgendaEventModel(
            id: "e", startTime: startTime, endTime: endTime, startDate: start, endDate: end, title: "New Event"
        )
    }

    func testStartsTodayEndsTomorrow() {
        let model = event(start: date(22, 15, 45), end: date(23, 16, 45))
        XCTAssertEqual(
            DayTimelineSegmentLabel.build(event: model, day: day(22), calendar: calendar),
            .startsHereEndsLater(destination: "Tomorrow 16:45")
        )
    }

    func testTwelveHourEndpoints() {
        let model = event(start: date(22, 15, 45), end: date(23, 16, 45))
        XCTAssertEqual(
            DayTimelineSegmentLabel.build(event: model, day: day(22), calendar: calendar, format: .twelveHour),
            .startsHereEndsLater(destination: "Tomorrow 4:45pm")
        )
        XCTAssertEqual(
            DayTimelineSegmentLabel.build(event: model, day: day(23), calendar: calendar, format: .twelveHour),
            .endsHere(since: "Yesterday", until: "4:45pm")
        )
    }

    func testFinalDayAdjacentToStartUsesSinceYesterday() {
        let model = event(start: date(22, 15, 45), end: date(23, 16, 45))
        XCTAssertEqual(
            DayTimelineSegmentLabel.build(event: model, day: day(23), calendar: calendar),
            .endsHere(since: "Yesterday", until: "16:45")
        )
    }

    func testFinalDayFartherBackUsesWeekdayAndDate() {
        let model = event(start: date(22, 15, 45), end: date(25, 16, 45))
        XCTAssertEqual(
            DayTimelineSegmentLabel.build(event: model, day: day(25), calendar: calendar),
            .endsHere(since: "Tue 22 Sep", until: "16:45")
        )
    }

    func testIntermediateDayIsJustContinues() {
        let model = event(start: date(22, 15, 45), end: date(25, 16, 45))
        XCTAssertEqual(DayTimelineSegmentLabel.build(event: model, day: day(23), calendar: calendar), .continuesThroughDay)
    }

    func testExactMidnightEndUsesMidnightWording() {
        let model = event(start: date(22, 15, 0), end: date(23, 0, 0), startTime: "15:00", endTime: "00:00")
        XCTAssertEqual(
            DayTimelineSegmentLabel.build(event: model, day: day(22), calendar: calendar),
            .startsHereEndsLater(destination: "Midnight")
        )
        XCTAssertNil(DayTimelineSegmentLabel.build(event: model, day: day(23), calendar: calendar))
    }

    func testOrdinarySameDayEventIsUnaffected() {
        let model = event(start: date(22, 15, 45), end: date(22, 16, 45))
        XCTAssertEqual(DayTimelineSegmentLabel.build(event: model, day: day(22), calendar: calendar), .sameDay)
    }
}
