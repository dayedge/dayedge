import XCTest
@testable import Shell
@testable import Domain
@testable import Agenda

final class AgendaNowTargetTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 21, hour: hour, minute: minute, second: second
        ))!
    }

    private func event(
        id: String,
        start: String? = nil,
        end: String? = nil,
        status: EventStatus = .confirmed
    ) -> AgendaEventModel {
        AgendaEventModel(id: id, startTime: start, endTime: end, title: id, status: status)
    }

    func testOngoingEventUsesInclusiveStartAndExclusiveEnd() {
        let meeting = event(id: "meeting", start: "10:00", end: "11:00")

        XCTAssertEqual(
            preferredNowTarget(on: date(0), events: [meeting], now: date(10), calendar: calendar),
            .ongoing(eventIDs: ["meeting"])
        )
        XCTAssertEqual(
            preferredNowTarget(on: date(0), events: [meeting], now: date(11), calendar: calendar),
            .endOfDay
        )
    }

    func testMostRecentlyStartedOverlappingEventIsScrollTarget() {
        let long = event(id: "long", start: "09:00", end: "12:00")
        let recent = event(id: "recent", start: "10:30", end: "11:30")

        XCTAssertEqual(
            preferredNowTarget(on: date(0), events: [long, recent], now: date(11), calendar: calendar),
            .ongoing(eventIDs: ["long", "recent"])
        )
    }

    func testFreeUntilDeadlineRemainsVisibleForTheEntireGap() {
        let eventAtEleven = event(id: "next", start: "11:00", end: "12:00")

        XCTAssertEqual(
            preferredNowTarget(on: date(0), events: [eventAtEleven], now: date(10, 30), calendar: calendar),
            .gap(nextItemID: "next", until: date(11))
        )
        XCTAssertEqual(
            preferredNowTarget(on: date(0), events: [eventAtEleven], now: date(10, 31), calendar: calendar),
            .gap(nextItemID: "next", until: date(11))
        )
    }

    func testBeforeBetweenAndAfterEventsKeepTheNowAnchorOnToday() {
        let morning = event(id: "morning", start: "08:00", end: "09:00")
        let afternoon = event(id: "afternoon", start: "14:00", end: "15:00")

        XCTAssertEqual(
            preferredNowTarget(on: date(0), events: [morning, afternoon], now: date(7), calendar: calendar),
            .gap(nextItemID: "morning", until: date(8))
        )
        XCTAssertEqual(
            preferredNowTarget(on: date(0), events: [morning, afternoon], now: date(10), calendar: calendar),
            .gap(nextItemID: "afternoon", until: date(14))
        )
        XCTAssertEqual(
            preferredNowTarget(on: date(0), events: [morning, afternoon], now: date(16), calendar: calendar),
            .endOfDay
        )
    }

    func testAllDayAndCancelledEventsDoNotParticipate() {
        let allDay = event(id: "holiday")
        let cancelled = event(id: "cancelled", start: "10:00", end: "11:00", status: .cancelled)

        XCTAssertEqual(
            preferredNowTarget(on: date(0), events: [allDay, cancelled], now: date(10, 30), calendar: calendar),
            .day
        )
    }

    func testOvernightEventProducesAValidInterval() throws {
        let overnight = event(id: "overnight", start: "23:00", end: "01:00")
        let interval = try XCTUnwrap(agendaInterval(for: overnight, on: date(0), calendar: calendar))

        XCTAssertEqual(interval.start, date(23))
        XCTAssertEqual(interval.duration, 2 * 60 * 60)
    }

    func testIntervalUsesWallClockTimesAcrossDaylightSavingChange() throws {
        var warsaw = Calendar(identifier: .gregorian)
        warsaw.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Warsaw"))
        let springForwardDay = try XCTUnwrap(
            warsaw.date(from: DateComponents(year: 2026, month: 3, day: 29))
        )
        let event = event(id: "dst", start: "01:30", end: "03:30")
        let interval = try XCTUnwrap(agendaInterval(for: event, on: springForwardDay, calendar: warsaw))

        XCTAssertEqual(interval.duration, 60 * 60)
    }

    func testCrossingMidnightEventIsOngoingOnItsFinalDayUsingRealDates() throws {
        let start = date(23)  // 23:00 on the reference day (2026-09-21)
        let end = try XCTUnwrap(calendar.date(byAdding: .hour, value: 3, to: start))  // 02:00 the next day
        let crossing = AgendaEventModel(
            id: "crossing", startTime: "23:00", endTime: "02:00",
            startDate: start, endDate: end, title: "crossing"
        )
        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: start)))
        let midnightPlusOneHour = try XCTUnwrap(calendar.date(byAdding: .hour, value: 1, to: nextDay))

        XCTAssertEqual(
            preferredNowTarget(on: nextDay, events: [crossing], now: midnightPlusOneHour, calendar: calendar),
            .ongoing(eventIDs: ["crossing"])
        )
    }

    func testMultiDaySpanIsOngoingOnAnIntermediateDayUsingRealDates() throws {
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 15, minute: 45)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 16, minute: 45)))
        let spanning = AgendaEventModel(
            id: "conference", startTime: "15:45", endTime: "16:45",
            startDate: start, endDate: end, title: "conference"
        )
        let intermediateDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 22)))
        let midday = try XCTUnwrap(calendar.date(byAdding: .hour, value: 12, to: intermediateDay))

        XCTAssertEqual(
            preferredNowTarget(on: intermediateDay, events: [spanning], now: midday, calendar: calendar),
            .ongoing(eventIDs: ["conference"])
        )
    }

    func testGapUsesAnAbsoluteDeadlineLabel() {
        XCTAssertEqual(
            AgendaNowTarget.gap(nextItemID: "next", until: date(11)).statusLabel(calendar: calendar),
            "Free until 11:00"
        )
    }

    func testResolverRoundsNowToTheDisplayedMinute() {
        let next = event(id: "next", start: "09:00", end: "10:00")
        let target = preferredNowTarget(
            on: date(0), events: [next], now: date(7, 40, 59), calendar: calendar
        )

        XCTAssertEqual(target, .gap(nextItemID: "next", until: date(9)))
    }

}

@MainActor
final class PopoverPresentationCoordinatorTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    func testFirstOpenIsFresh() {
        let coordinator = PopoverPresentationCoordinator()
        coordinator.willOpen(at: base)
        XCTAssertEqual(coordinator.openRequest?.behavior, .todayNow)
    }

    func testReopenWithinTenMinutesPreserves() {
        let coordinator = PopoverPresentationCoordinator()
        coordinator.didHide(at: base)
        coordinator.willOpen(at: base.addingTimeInterval(599))
        XCTAssertEqual(coordinator.openRequest?.behavior, .preserve)
    }

    func testReopenAfterTenMinutesIsFresh() {
        let coordinator = PopoverPresentationCoordinator()
        coordinator.didHide(at: base)
        coordinator.willOpen(at: base.addingTimeInterval(601))
        XCTAssertEqual(coordinator.openRequest?.behavior, .todayNow)
    }
}
