import Foundation
import Observation
import Domain
import UI

/// Owns only the month grid now — agenda-section state/paging lives in the
/// separate `AgendaSectionStore`, deliberately a distinct `@Observable`
/// object so a grid-only change here never forces SwiftUI to re-diff the
/// (much larger) agenda view tree. See `AgendaSectionStore`'s doc comment.
@Observable
package final class CalendarViewModel {
    private let dataProvider: CalendarDataProviding
    private var calendar: Calendar

    package private(set) var visibleMonth: Date
    package private(set) var selectedDate: Date
    package private(set) var days: [DayCellModel] = []

    package init(dataProvider: CalendarDataProviding = MockCalendarDataProvider(),
                 calendar: Calendar = .autoupdatingCurrent,
                 visibleMonth: Date,
                 selectedDate: Date) {
        self.dataProvider = dataProvider
        var cal = calendar
        cal.firstWeekday = GeneralSettings.weekStart().firstWeekday()
        self.calendar = cal
        self.visibleMonth = visibleMonth
        self.selectedDate = selectedDate
        reload()
    }

    /// The grid's calendar (its first weekday) with the stored date format.
    private var dateFormatter: DatePresentationFormatter {
        var formatter = DatePresentationFormatter.current
        formatter.calendar = calendar
        return formatter
    }

    package var monthTitle: String {
        dateFormatter.month(visibleMonth, abbreviated: false)
    }

    package var yearTitle: String {
        dateFormatter.year(visibleMonth)
    }

    package var weekdaySymbols: [String] {
        dateFormatter.weekdaySymbols(.abbreviated).map { $0.uppercased() }
    }

    /// Week-of-year label for each row of the current grid.
    package var weekNumbers: [Int] {
        WeekNumbers.labels(forGridStarting: days.map(\.date), calendar: calendar)
    }

    /// Applies the "Week starts on" setting to the grid.
    package func setFirstWeekday(_ weekday: Int) {
        guard calendar.firstWeekday != weekday else { return }
        calendar.firstWeekday = weekday
        reload()
    }

    /// Recomputes the 42-cell month grid.
    package func reload() {
        days = dataProvider.days(for: visibleMonth, selectedDate: selectedDate, calendar: calendar)
    }

    /// Keyboard month navigation also chooses a concrete landing day for
    /// the grid: previous month starts at day one, next month at its last
    /// day, except that returning to the real current month lands on
    /// today from either direction. Callers are responsible for also
    /// covering `landingDate` in the agenda store (see `RootView`).
    @discardableResult
    package func moveToAdjacentMonth(direction: CalendarArrowKey) -> Date? {
        let monthDelta: Int
        switch direction {
        case .left: monthDelta = -1
        case .right: monthDelta = 1
        case .up, .down: return nil
        }

        guard let targetMonth = calendar.date(byAdding: .month, value: monthDelta, to: visibleMonth),
              let monthInterval = calendar.dateInterval(of: .month, for: targetMonth) else { return nil }

        let today = calendar.startOfDay(for: Date())
        let landingDate: Date
        if calendar.isDate(targetMonth, equalTo: today, toGranularity: .month) {
            landingDate = today
        } else if direction == .left {
            landingDate = monthInterval.start
        } else {
            landingDate = calendar.date(byAdding: .day, value: -1, to: monthInterval.end) ?? monthInterval.start
        }

        visibleMonth = targetMonth
        selectedDate = landingDate
        reload()
        return landingDate
    }

    /// Moves the grid's selection/highlight. Callers are responsible for
    /// also covering `date` in the agenda store when it might fall outside
    /// the currently loaded window (see `RootView`).
    package func select(date: Date) {
        guard !calendar.isDate(date, inSameDayAs: selectedDate) else { return }
        let changesVisibleMonth = !calendar.isDate(date, equalTo: visibleMonth, toGranularity: .month)
        selectedDate = date
        if changesVisibleMonth {
            visibleMonth = date
            reload()
        }
    }

    /// Shows the given month without changing which day is selected — for
    /// "just take me to September" style navigation, as opposed to
    /// `select(date:)` which also means "and this specific day."
    package func jumpToMonth(_ date: Date) {
        visibleMonth = date
        reload()
    }

    package func goToPreviousDay() {
        guard let newDate = calendar.date(byAdding: .day, value: -1, to: selectedDate) else { return }
        select(date: newDate)
    }

    package func goToNextDay() {
        guard let newDate = calendar.date(byAdding: .day, value: 1, to: selectedDate) else { return }
        select(date: newDate)
    }

    package var isSelectedDateToday: Bool {
        calendar.isDateInToday(selectedDate)
    }

    /// For the month grid's hover "glance" preview — a specific arbitrary
    /// day's events, computed on demand rather than kept in observed
    /// state (it's requested for at most one day at a time, briefly).
    /// Deliberately not routed through `AgendaSectionStore` — this is a
    /// different, already-narrow/cheap, single-day provider call.
    package func events(onDate date: Date) -> [AgendaEventModel] {
        dataProvider.events(for: date, calendar: calendar)
    }
}
