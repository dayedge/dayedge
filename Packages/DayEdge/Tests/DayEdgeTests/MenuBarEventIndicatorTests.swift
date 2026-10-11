import XCTest
@testable import Shell
@testable import Domain

final class MenuBarEventIndicatorTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: hour, minute: minute))!
    }

    private func event(_ id: String, _ start: String, _ end: String) -> AgendaEventModel {
        AgendaEventModel(id: id, startTime: start, endTime: end, title: id)
    }

    private var configuration: MenuBarEventIndicatorConfiguration {
        var configuration = MenuBarEventIndicatorConfiguration.default
        configuration.isEnabled = true
        return configuration
    }

    func testUpcomingEventAppearsInsideLeadWindowAndUsesCeilingMinutes() {
        let meeting = event("Planning", "10:00", "11:00")
        let state = MenuBarEventIndicatorResolver.resolve(
            events: [meeting], on: date(0), now: date(9, 45).addingTimeInterval(20),
            calendar: calendar, configuration: configuration
        )

        XCTAssertEqual(state, .upcoming(event: meeting, minutesUntilStart: 15))
        XCTAssertEqual(
            state?.label(configuration: configuration, calendar: calendar),
            "15m · Planning →11:00"
        )
    }

    func testLabelsFollowTheTimeFormat() {
        let meeting = AgendaEventModel(id: "Planning", startTime: "10:00", endTime: "11:00",
                                       startDate: date(10), endDate: date(11), title: "Planning")
        let upcoming = MenuBarEventIndicatorState.upcoming(event: meeting, minutesUntilStart: 15)
        XCTAssertEqual(upcoming.label(configuration: configuration, calendar: calendar, format: .twelveHour),
                       "15m · Planning →11:00am")
        XCTAssertEqual(MenuBarEventIndicatorState.free(until: date(15, 30))
            .label(configuration: configuration, calendar: calendar, format: .twelveHour), "Free until 3:30pm")
    }

    func testEventOutsideLeadWindowIsHidden() {
        XCTAssertNil(MenuBarEventIndicatorResolver.resolve(
            events: [event("Later", "10:00", "11:00")], on: date(0), now: date(9, 44),
            calendar: calendar, configuration: configuration
        ))
    }

    func testOngoingEventChangesToRemainingTimeInFinalTenMinutes() {
        let meeting = event("Review", "09:00", "10:00")
        let ordinary = MenuBarEventIndicatorResolver.resolve(
            events: [meeting], on: date(0), now: date(9, 30),
            calendar: calendar, configuration: configuration
        )
        let nearEnd = MenuBarEventIndicatorResolver.resolve(
            events: [meeting], on: date(0), now: date(9, 52),
            calendar: calendar, configuration: configuration
        )

        XCTAssertEqual(ordinary, .ongoing(event: meeting, minutesRemaining: nil))
        XCTAssertEqual(nearEnd, .ongoing(event: meeting, minutesRemaining: 8))
    }

    func testFreeTransitionRequiresRecentMeetingAndMeaningfulGap() {
        var config = configuration
        config.showsFreeTimeTransition = true
        config.freeTimeTransitionMinutes = 5
        config.minimumFreeGapMinutes = 30
        let previous = event("Previous", "09:00", "10:00")
        let next = event("Next", "11:00", "12:00")

        XCTAssertEqual(
            MenuBarEventIndicatorResolver.resolve(
                events: [previous, next], on: date(0), now: date(10, 4),
                calendar: calendar, configuration: config
            ),
            .free(until: date(11))
        )
        XCTAssertNil(MenuBarEventIndicatorResolver.resolve(
            events: [previous, next], on: date(0), now: date(10, 6),
            calendar: calendar, configuration: config
        ))
    }

    func testUpcomingCountdownTakesPriorityOverFreeTransition() {
        var config = configuration
        config.leadTimeMinutes = 15
        config.showsFreeTimeTransition = true
        config.freeTimeTransitionMinutes = 10
        config.minimumFreeGapMinutes = 15
        let previous = event("Previous", "09:00", "10:00")
        let next = event("Next", "10:15", "11:00")

        XCTAssertEqual(
            MenuBarEventIndicatorResolver.resolve(
                events: [previous, next], on: date(0), now: date(10, 2),
                calendar: calendar, configuration: config
            ),
            .upcoming(event: next, minutesUntilStart: 13)
        )
    }

    func testDisabledIndicatorAlwaysReturnsNil() {
        var disabledConfiguration = configuration
        disabledConfiguration.isEnabled = false
        XCTAssertNil(MenuBarEventIndicatorResolver.resolve(
            events: [event("Meeting", "09:00", "10:00")], on: date(0), now: date(9),
            calendar: calendar, configuration: disabledConfiguration
        ))
    }
}
