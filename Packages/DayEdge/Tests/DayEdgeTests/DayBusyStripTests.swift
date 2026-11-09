import XCTest
@testable import Domain
@testable import Agenda

/// The month cell's day strip: meetings across 8–17, the earlier one
/// keeping overlapping time.
final class DayBusyStripTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private var day: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 26))! }
    private let red = RGBAColor(red: 1, green: 0, blue: 0, alpha: 1)
    private let blue = RGBAColor(red: 0, green: 0, blue: 1, alpha: 1)

    private func at(_ hour: Double, dayOffset: Int = 0) -> Date {
        calendar.date(byAdding: .day, value: dayOffset, to: day)!.addingTimeInterval(hour * 3600)
    }

    private func event(_ start: Double, _ end: Double, tint: RGBAColor = .placeholder, startDay: Int = 0,
                       status: EventStatus = .confirmed, response: EventAttendee.Status? = nil) -> AgendaEventModel {
        AgendaEventModel(startTime: "00:00", endTime: "00:00", startDate: at(start, dayOffset: startDay), endDate: at(end),
                         title: "Meeting", status: status, tint: tint, myResponseStatus: response)
    }

    private func segments(_ events: [AgendaEventModel]) -> [DayBusyStrip.Segment] {
        DayBusyStrip.segments(events: events, day: day, hours: 8..<17, calendar: calendar)
    }

    func testAMeetingMapsToItsShareOfTheWorkday() {
        let strip = segments([event(9, 12)])
        XCTAssertEqual(strip.map(\.start), [1.0 / 9])
        XCTAssertEqual(strip.map(\.end), [4.0 / 9])
    }

    func testTheEarlierMeetingKeepsOverlappingTime() {
        let strip = segments([event(10, 12, tint: blue), event(9, 11, tint: red)])
        XCTAssertEqual(strip, [.init(start: 1.0 / 9, end: 3.0 / 9, tint: red), .init(start: 3.0 / 9, end: 4.0 / 9, tint: blue)])
    }

    func testAMeetingInsideAnEarlierOneAddsNothing() {
        XCTAssertEqual(segments([event(9, 12), event(10, 11)]).count, 1)
    }

    func testAMeetingOutsideTheWorkdayAddsNothing() {
        XCTAssertTrue(segments([event(18, 19)]).isEmpty)
    }

    func testAMeetingAcrossTheWorkdaysEdgeIsClipped() {
        let strip = segments([event(16, 18)])
        XCTAssertEqual(strip.map(\.end), [1])
    }

    func testAllDayEventsTakeNoTime() {
        let allDay = AgendaEventModel(startDate: at(0), endDate: at(24), title: "Holiday")
        XCTAssertTrue(segments([allDay]).isEmpty)
    }

    func testCancelledMeetingsTakeNoTime() {
        XCTAssertTrue(segments([event(9, 10, status: .cancelled)]).isEmpty)
    }

    func testDeclinedMeetingsTakeNoTime() {
        XCTAssertTrue(segments([event(9, 10, response: .declined)]).isEmpty)
    }

    func testAMeetingFromTheEveningBeforeIsClippedToTheWorkday() {
        let strip = segments([event(22, 9, startDay: -1)])
        XCTAssertEqual(strip.map(\.start), [0])
        XCTAssertEqual(strip.map(\.end), [1.0 / 9])
    }
}
