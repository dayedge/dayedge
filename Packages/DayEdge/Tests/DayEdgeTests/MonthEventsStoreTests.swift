import XCTest
@testable import Domain
@testable import Agenda

@MainActor
final class MonthEventsStoreTests: XCTestCase {
    private final class CountingProvider: CalendarDataProviding, @unchecked Sendable {
        var sections: [AgendaDaySection] = []
        private(set) var ranges: [DateInterval] = []
        func days(for monthAnchor: Date, selectedDate: Date, calendar: Calendar) -> [DayCellModel] { [] }
        func agendaSections(in range: DateInterval, calendar: Calendar) async -> [AgendaDaySection] {
            ranges.append(range)
            return sections.filter { range.contains($0.date) }
        }
        func events(for date: Date, calendar: Calendar) -> [AgendaEventModel] { [] }
    }

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    private func day(_ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
    }

    private func event(_ id: String, on date: Date) -> AgendaDaySection {
        AgendaDaySection(date: date, events: [AgendaEventModel(id: id, title: id)])
    }

    func testShowingAMonthFindsItsEventsByDay() async {
        let provider = CountingProvider()
        provider.sections = [event("a", on: day(10, 5))]
        let store = MonthEventsStore(dataProvider: provider, calendar: calendar, notificationCenter: NotificationCenter())
        await store.show(month: day(10, 1))
        XCTAssertEqual(store.events(on: day(10, 5).addingTimeInterval(3600)).map(\.id), ["a"])
        XCTAssertTrue(store.events(on: day(10, 6)).isEmpty)
    }

    func testTheGridsOverflowDaysAreCovered() async {
        let provider = CountingProvider()
        provider.sections = [event("before", on: day(9, 28)), event("after", on: day(11, 8))]
        let store = MonthEventsStore(dataProvider: provider, calendar: calendar, notificationCenter: NotificationCenter())
        await store.show(month: day(10, 1))
        XCTAssertEqual(store.events(on: day(9, 28)).map(\.id), ["before"])
        XCTAssertEqual(store.events(on: day(11, 8)).map(\.id), ["after"])
    }

    func testBothNeighboursAreReadiedAfterAMonthIsShown() async {
        let provider = CountingProvider()
        let store = MonthEventsStore(dataProvider: provider, calendar: calendar, notificationCenter: NotificationCenter())
        await store.show(month: day(10, 1))
        XCTAssertEqual(provider.ranges.count, 3)
    }

    func testMovingToAReadiedNeighbourShowsItWithoutFetchingIt() async {
        let provider = CountingProvider()
        provider.sections = [event("n", on: day(11, 12))]
        let store = MonthEventsStore(dataProvider: provider, calendar: calendar, notificationCenter: NotificationCenter())
        await store.show(month: day(10, 1))
        let fetchedBefore = provider.ranges.count
        await store.show(month: day(11, 1))
        XCTAssertEqual(store.events(on: day(11, 12)).map(\.id), ["n"])
        // Only November's own next neighbour (December) is new.
        XCTAssertEqual(provider.ranges.count, fetchedBefore + 1)
    }

    func testACalendarChangeFetchesTheShownMonthAgain() async {
        let provider = CountingProvider()
        let center = NotificationCenter()
        let store = MonthEventsStore(dataProvider: provider, calendar: calendar, notificationCenter: center)
        await store.show(month: day(10, 1))
        provider.sections = [event("new", on: day(10, 5))]
        center.post(name: .calendarEventsDidChange, object: nil)
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(store.events(on: day(10, 5)).map(\.id), ["new"])
    }

    func testAfterAChangeANeighbourIsFetchedAgainNotReused() async {
        let provider = CountingProvider()
        let center = NotificationCenter()
        let store = MonthEventsStore(dataProvider: provider, calendar: calendar, notificationCenter: center)
        await store.show(month: day(10, 1))
        provider.sections = [event("moved", on: day(11, 12))]
        center.post(name: .calendarEventsDidChange, object: nil)
        await store.show(month: day(11, 1))
        XCTAssertEqual(store.events(on: day(11, 12)).map(\.id), ["moved"])
    }

    func testARepeatedShowOfAReadyMonthFetchesNothing() async {
        let provider = CountingProvider()
        let store = MonthEventsStore(dataProvider: provider, calendar: calendar, notificationCenter: NotificationCenter())
        await store.show(month: day(10, 1))
        let fetched = provider.ranges.count
        await store.show(month: day(10, 15))
        XCTAssertEqual(provider.ranges.count, fetched)
    }
}
