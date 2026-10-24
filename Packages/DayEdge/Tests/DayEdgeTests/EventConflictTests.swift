import XCTest
@testable import Shell
@testable import Domain
@testable import Intelligence

/// A new event's time against what's there: red, yellow or green.
final class EventConflictTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: hour, minute: minute))!
    }
    private func event(_ start: Int, _ end: Int, _ response: EventAttendee.Status? = nil,
                       status: EventStatus = .confirmed, allDay: Bool = false) -> AgendaEventModel {
        AgendaEventModel(startTime: allDay ? nil : "\(start):00", endTime: allDay ? nil : "\(end):00",
                         startDate: at(start), endDate: at(end), title: "x", status: status, myResponseStatus: response)
    }
    private func check(_ events: [AgendaEventModel]) -> EventConflict {
        EventConflict.check(start: at(11), end: at(12), against: events)
    }

    func testFreeWhenNothingOverlaps() {
        XCTAssertEqual(check([]), .free)
        XCTAssertEqual(check([event(10, 11), event(12, 13)]), .free, "touching ends don't overlap")
    }

    func testAcceptedOrOwnEventsAreBusy() {
        XCTAssertEqual(check([event(10, 12, .accepted)]), .busy)
        XCTAssertEqual(check([event(11, 12)]), .busy, "your own event needs no reply")
    }

    func testNotYetAcceptedIsUnconfirmed() {
        XCTAssertEqual(check([event(11, 13, .pending)]), .unconfirmed)
        XCTAssertEqual(check([event(11, 13, .tentative)]), .unconfirmed)
        XCTAssertEqual(check([event(11, 13, .pending), event(10, 12, .accepted)]), .busy, "accepted wins")
    }

    func testTheOverlapShownIsTheOneThatDecidesTheColour() {
        let pending = event(10, 12, .pending)
        let accepted = event(11, 13, .accepted)
        XCTAssertEqual(EventConflict.overlap(start: at(11), end: at(12), against: [pending, accepted])?.event, accepted)
        XCTAssertEqual(EventConflict.overlap(start: at(11), end: at(12), against: [pending])?.event, pending)
        XCTAssertNil(EventConflict.overlap(start: at(11), end: at(12), against: []))
    }

    func testDeclinedCancelledAndAllDayNeverBlock() {
        XCTAssertEqual(check([event(11, 12, .declined)]), .free)
        XCTAssertEqual(check([event(11, 12, status: .cancelled)]), .free)
        XCTAssertEqual(check([event(0, 23, allDay: true)]), .free)
    }
}

/// The event editor's values: what it makes of a draft and gives back (the timing rules are `EventTimingTests`).
final class EventQuickAddEditTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private func edit(start: Date, end: Date) -> EventQuickAddEdit {
        let draft = EventDraft(title: "Lunch", start: start, end: end)
        return EventQuickAddEdit(draft: draft, calendar: calendar)
    }

    func testAnEventOverSeveralDaysKeepsItsEnd() {
        let value = edit(start: at(24, 22), end: at(26, 6))
        XCTAssertEqual([value.timing.firstDay, value.timing.lastDay], [at(24, 0), at(26, 0)])
        XCTAssertEqual(value.eventDraft(calendar: calendar).end, at(26, 6))
    }

    func testAllDayDraftsKeepTheirSpan() {
        let draft = EventDraft(title: "Conference", start: at(3, 0), end: at(6, 0), isAllDay: true)
        let value = EventQuickAddEdit(draft: draft, calendar: calendar)
        let event = value.eventDraft(calendar: calendar)
        XCTAssertTrue(event.isAllDay)
        XCTAssertEqual([event.start, event.end], [at(3, 0), at(6, 0)])
    }
}
