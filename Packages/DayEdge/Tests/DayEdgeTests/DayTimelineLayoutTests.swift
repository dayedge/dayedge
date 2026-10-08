import XCTest
@testable import Shell
@testable import Domain
@testable import Agenda

final class DayTimelineLayoutTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private func day(_ day: Int) -> Date {
        date(day, 0)
    }

    private func timeString(_ hour: Int, _ minute: Int = 0) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    private func event(id: String = "event", start: Date, end: Date) -> AgendaEventModel {
        let startComponents = calendar.dateComponents([.hour, .minute], from: start)
        let endComponents = calendar.dateComponents([.hour, .minute], from: end)
        return AgendaEventModel(
            id: id,
            startTime: timeString(startComponents.hour ?? 0, startComponents.minute ?? 0),
            endTime: timeString(endComponents.hour ?? 0, endComponents.minute ?? 0),
            startDate: start,
            endDate: end,
            title: id
        )
    }

    func testCrossingMidnightEventClipsToEndOfStartDay() {
        let crossing = event(start: date(22, 22, 0), end: date(23, 2, 0))
        let positioned = DayTimelineLayout.layout(events: [crossing], day: day(22), calendar: calendar)

        XCTAssertEqual(positioned.count, 1)
        XCTAssertEqual(positioned.first?.startMinutes, 22 * 60)
        XCTAssertEqual(positioned.first?.endMinutes, 24 * 60)
    }

    func testCrossingMidnightEventClipsToStartOfEndDay() {
        let crossing = event(start: date(22, 22, 0), end: date(23, 2, 0))
        let positioned = DayTimelineLayout.layout(events: [crossing], day: day(23), calendar: calendar)

        XCTAssertEqual(positioned.count, 1)
        XCTAssertEqual(positioned.first?.startMinutes, 0)
        XCTAssertEqual(positioned.first?.endMinutes, 2 * 60)
    }

    func testIntermediateDayFillsTheEntireVisibleDay() {
        let long = event(start: date(22, 15, 45), end: date(25, 16, 45))
        let positioned = DayTimelineLayout.layout(events: [long], day: day(23), calendar: calendar)

        XCTAssertEqual(positioned.first?.startMinutes, 0)
        XCTAssertEqual(positioned.first?.endMinutes, 24 * 60)
    }

    func testEventEndingExactlyAtMidnightProducesNoFollowingDayRow() {
        let crossing = event(start: date(22, 15, 0), end: date(23, 0, 0))
        let positioned = DayTimelineLayout.layout(events: [crossing], day: day(23), calendar: calendar)

        XCTAssertTrue(positioned.isEmpty)
    }

    func testSameDayEventIsUnaffected() {
        let plain = event(start: date(22, 9, 0), end: date(22, 10, 0))
        let positioned = DayTimelineLayout.layout(events: [plain], day: day(22), calendar: calendar)

        XCTAssertEqual(positioned.first?.startMinutes, 9 * 60)
        XCTAssertEqual(positioned.first?.endMinutes, 10 * 60)
    }
}
