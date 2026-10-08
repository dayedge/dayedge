import CalendarIndex
import SwiftUI
import XCTest
@testable import Shell
@testable import Domain
@testable import Platform

/// `CalendarProvider`'s projection over a scripted `CalendarEventSource`.
final class CalendarProviderTests: XCTestCase {
    private var calendar: Calendar!
    private var defaults: UserDefaults!
    private var visibility: SourceVisibilityStore!
    private var source: FakeCalendarEventSource!
    private var showsDeclined = false

    override func setUp() {
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        defaults = UserDefaults(suiteName: "CalendarProviderTests-\(UUID().uuidString)")
        visibility = SourceVisibilityStore(kind: .calendars, defaults: defaults)
        source = FakeCalendarEventSource(calendar: calendar)
        showsDeclined = false
    }

    private func provider(maxDots: Int = 4) -> CalendarProvider {
        CalendarProvider(source: source, visibilityStore: visibility, maxDotsPerDay: maxDots,
                         showsDeclined: { [unowned self] in self.showsDeclined })
    }

    private func day(_ value: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: value, hour: hour))!
    }

    private var october: DateInterval { calendar.dateInterval(of: .month, for: day(1))! }

    // MARK: - Month grid

    func testMonthGridHasFortyTwoCellsWithDotsInCalendarColorAndBuildsNoModels() {
        source.add("Standup", calendarID: "work", color: .red, at: day(5))
        let cells = provider().days(for: day(1), selectedDate: day(5), calendar: calendar)
        XCTAssertEqual(cells.count, 42)
        let fifth = cells.first { calendar.isDate($0.date, inSameDayAs: day(5)) }
        XCTAssertEqual(fifth?.dots, [DotStyle(tint: .red, isFilled: true)])
        XCTAssertEqual(fifth?.isSelected, true)
        XCTAssertEqual(source.modelsBuilt, 0, "the grid never builds full event models")
    }

    func testDotsKeepOneBeyondTheLimitForTheOverflowMarker() {
        for hour in 8..<16 { source.add("E\(hour)", at: day(7, hour: hour)) }
        let cells = provider(maxDots: 4).days(for: day(1), selectedDate: day(1), calendar: calendar)
        XCTAssertEqual(cells.first { calendar.isDate($0.date, inSameDayAs: day(7)) }?.dots.count, 5)
    }

    func testUnauthorizedSourceGivesNoGrid() {
        source.isAuthorized = false
        XCTAssertEqual(provider().days(for: day(1), selectedDate: day(1), calendar: calendar), [])
    }

    // MARK: - Filtering

    func testExcludedAndHiddenCalendarsAreDropped() async {
        source.add("Work", calendarID: "work", at: day(5))
        source.add("Excluded", calendarID: "excluded", at: day(5, hour: 10))
        source.add("Hidden", calendarID: "hidden", at: day(5, hour: 11))
        visibility.setEnabled(false, id: "excluded")
        visibility.toggle("hidden")

        let titles = await provider().agendaSections(in: october, calendar: calendar).flatMap(\.events).map(\.title)
        XCTAssertEqual(titles, ["Work"])
        let dots = provider().days(for: day(1), selectedDate: day(1), calendar: calendar)
            .first { calendar.isDate($0.date, inSameDayAs: day(5)) }?.dots
        XCTAssertEqual(dots?.count, 1)
    }

    func testDeclinedEventsHiddenUnlessShown() {
        source.add("Accepted", at: day(6))
        source.add("Declined", at: day(6, hour: 11), declined: true)
        XCTAssertEqual(provider().events(for: day(6), calendar: calendar).map(\.title), ["Accepted"])
        showsDeclined = true
        XCTAssertEqual(provider().events(for: day(6), calendar: calendar).map(\.title), ["Accepted", "Declined"])
    }

    // MARK: - Agenda and day

    func testAgendaSectionsStayInRangeSortedByStart() async {
        source.add("Later", at: day(8, hour: 15))
        source.add("Earlier", at: day(8, hour: 8))
        source.add("Outside", at: day(20))
        let range = DateInterval(start: day(7, hour: 0), end: day(9, hour: 0))
        let sections = await provider().agendaSections(in: range, calendar: calendar)
        XCTAssertEqual(sections.map(\.date), [calendar.startOfDay(for: day(8))])
        XCTAssertEqual(sections.first?.events.map(\.title), ["Earlier", "Later"])
    }

    func testTodayIsMarked() async {
        let now = Date()
        source.add("Now", at: now)
        let sections = await provider().agendaSections(in: DateInterval(start: now.addingTimeInterval(-3600), duration: 7200),
                                                       calendar: calendar)
        XCTAssertEqual(sections.first?.isToday, calendar.isDateInToday(now))
    }

    func testSearchPassesVisibilityAndDeclinedToTheSource() async {
        visibility.toggle("hidden")
        visibility.setEnabled(false, id: "excluded")
        _ = await provider().searchEventMatches(.plain("standup"))
        XCTAssertEqual(source.lastSearch?.excluded, ["hidden", "excluded"])
        XCTAssertEqual(source.lastSearch?.includesDeclined, false)
        showsDeclined = true
        _ = await provider().searchEventMatches(.plain("standup"))
        XCTAssertEqual(source.lastSearch?.includesDeclined, true)
    }

    func testEventsForOneDaySorted() {
        source.add("B", at: day(9, hour: 14))
        source.add("A", at: day(9, hour: 9))
        source.add("Other day", at: day(10))
        XCTAssertEqual(provider().events(for: day(9), calendar: calendar).map(\.title), ["A", "B"])
    }
}

/// Scripted events, indexed by start day; counts built models.
private final class FakeCalendarEventSource: CalendarEventSource {
    private let calendar: Calendar
    private var events: [(start: Date, event: SourceEvent)] = []
    var isAuthorized = true
    private(set) var modelsBuilt = 0

    init(calendar: Calendar) {
        self.calendar = calendar
    }

    func add(_ title: String, calendarID: String = "work", color: RGBAColor = .blue, at start: Date, declined: Bool = false) {
        let marker = SourceMarker(calendarIdentifier: calendarID, startDate: start, isDeclinedByUser: declined, dotTint: color)
        let event = SourceEvent(marker: marker,
                                makeModel: { [unowned self] in
                                    self.modelsBuilt += 1
                                    return AgendaEventModel(startDate: start, title: title)
                                })
        events.append((start, event))
    }

    func markersByDaySync(in window: DateInterval, calendar: Calendar) -> [Date: [SourceMarker]] {
        eventsByDaySync(in: window, calendar: calendar).mapValues { $0.map(\.marker) }
    }

    func eventsByDaySync(in window: DateInterval, calendar: Calendar) -> [Date: [SourceEvent]] {
        guard isAuthorized else { return [:] }
        return Dictionary(grouping: events.filter { window.contains($0.start) }, by: { calendar.startOfDay(for: $0.start) })
            .mapValues { $0.map(\.event) }
    }

    func eventsByDay(in window: DateInterval, calendar: Calendar) async -> [Date: [SourceEvent]] {
        eventsByDaySync(in: window, calendar: calendar)
    }

    private(set) var lastSearch: (excluded: Set<String>, includesDeclined: Bool)?

    func searchMatches(_ request: SearchRequest) -> [CalendarIndex.SearchMatch] {
        lastSearch = (request.excludedCalendars, request.includesDeclined)
        return []
    }
}
