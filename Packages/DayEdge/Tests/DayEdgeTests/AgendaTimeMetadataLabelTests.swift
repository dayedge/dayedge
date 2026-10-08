import XCTest
@testable import Shell
@testable import Domain
@testable import UI

final class AgendaTimeMetadataLabelTests: XCTestCase {
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

    func testStartsTodayEndsTomorrowUsesDashNotArrow() {
        let model = event(start: date(22, 15, 45), end: date(23, 16, 45))
        let label = AgendaTimeMetadataLabel.build(event: model, day: day(22), calendar: calendar)
        XCTAssertEqual(label, .startsHereEndsLater(start: "15:45", destination: "Tomorrow 16:45"))
        XCTAssertEqual(label?.displayText, "15:45 – Tomorrow 16:45")
        XCTAssertFalse(label!.displayText.contains("→"))
    }

    func testEndsHereIsContinuesDashUntil() {
        let model = event(start: date(22, 15, 45), end: date(23, 16, 45))
        let label = AgendaTimeMetadataLabel.build(event: model, day: day(23), calendar: calendar)
        XCTAssertEqual(label, .endsHere(until: "16:45"))
        XCTAssertEqual(label?.displayText, "Continues – 16:45")
    }

    func testIntermediateDayIsJustContinues() {
        let model = event(start: date(22, 15, 45), end: date(25, 16, 45))
        let label = AgendaTimeMetadataLabel.build(event: model, day: day(23), calendar: calendar)
        XCTAssertEqual(label, .continuesThroughDay)
        XCTAssertEqual(label?.displayText, "Continues")
    }

    func testExactMidnightEndUsesCapitalizedMidnightWording() {
        let model = event(start: date(22, 15, 0), end: date(23, 0, 0), startTime: "15:00", endTime: "00:00")
        let label = AgendaTimeMetadataLabel.build(event: model, day: day(22), calendar: calendar)
        XCTAssertEqual(label, .startsHereEndsLater(start: "15:00", destination: "Midnight"))
        XCTAssertEqual(label?.displayText, "15:00 – Midnight")
    }

    func testOrdinarySameDayEventIsUnaffected() {
        let model = event(start: date(22, 15, 45), end: date(22, 16, 45))
        let label = AgendaTimeMetadataLabel.build(event: model, day: day(22), calendar: calendar)
        XCTAssertEqual(label, .sameDay(range: "15:45 – 16:45"))
        XCTAssertEqual(label?.displayText, "15:45 – 16:45")
    }

    /// The same rows in 12-hour time: compact, am/pm once within a half of
    /// the day, and from the event's real dates (not its stored strings).
    func testTwelveHourLabels() {
        let sameDay = event(start: date(22, 15, 45), end: date(22, 16, 45))
        XCTAssertEqual(AgendaTimeMetadataLabel.build(event: sameDay, day: day(22), calendar: calendar,
                                                     format: .twelveHour)?.displayText, "3:45–4:45pm")
        let acrossNoon = event(start: date(22, 11, 30), end: date(22, 12, 15))
        XCTAssertEqual(AgendaTimeMetadataLabel.build(event: acrossNoon, day: day(22), calendar: calendar,
                                                     format: .twelveHour)?.displayText, "11:30am–12:15pm")
        let crossing = event(start: date(22, 15, 45), end: date(23, 17, 0))
        XCTAssertEqual(AgendaTimeMetadataLabel.build(event: crossing, day: day(22), calendar: calendar,
                                                     format: .twelveHour)?.displayText, "3:45pm – Tomorrow 5:00pm")
        XCTAssertEqual(AgendaTimeMetadataLabel.build(event: crossing, day: day(23), calendar: calendar,
                                                     format: .twelveHour)?.displayText, "Continues – 5:00pm")
    }

    func testCrossingMonthBoundaryIncludesTheDate() {
        let model = event(start: date(29, 15, 45), end: date(29 + 4, 16, 45)) // 29 Sep -> 3 Oct
        let label = AgendaTimeMetadataLabel.build(event: model, day: day(29), calendar: calendar)
        XCTAssertEqual(label?.displayText, "15:45 – 3 Oct 16:45")
    }
}
