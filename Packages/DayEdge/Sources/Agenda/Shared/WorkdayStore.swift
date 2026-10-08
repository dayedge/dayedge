import Foundation
import Observation
import Domain

/// Workday summary + holiday marks for the visible month. Reads only
/// preferences and a `HolidayProviding` source; never EventKit. The summary
/// is available immediately (weekends only) and refines once holidays load.
@MainActor
@Observable
package final class WorkdayStore {
    package private(set) var configuration: WorkdaySettings.Configuration
    package private(set) var summary: MonthWorkdaySummary?
    /// dateKey → holiday name for the loaded year (covers grid overflow days).
    package private(set) var holidayNames: [String: String] = [:]

    @ObservationIgnored private let provider: HolidayProviding
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var month: Date?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var observer: NSObjectProtocol?

    package init(provider: HolidayProviding,
                 calendar: Calendar = .autoupdatingCurrent,
                 defaults: UserDefaults = .standard) {
        self.provider = provider
        self.calendar = calendar
        self.defaults = defaults
        self.configuration = WorkdaySettings.configuration(defaults: defaults)
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.preferencesChanged() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Summary for the header, nil when the count is switched off.
    package var headerSummary: MonthWorkdaySummary? {
        configuration.showCount ? summary : nil
    }

    /// Name to show for a marked holiday (nil when marking is off or the
    /// day is not a public holiday).
    package func holidayName(for date: Date) -> String? {
        guard configuration.markHolidays else { return nil }
        return holidayNames[WorkdayCalculator.dateKey(for: date, calendar: calendar)]
    }

    /// Whether to tint the day: a holiday on a work day only, so weekend
    /// holidays are never double-styled.
    package func isMarkedHoliday(_ date: Date) -> Bool {
        holidayName(for: date) != nil
            && !configuration.weekendWeekdays.contains(calendar.component(.weekday, from: date))
    }

    package func update(visibleMonth: Date) {
        month = visibleMonth
        refresh()
    }

    private func preferencesChanged() {
        let latest = WorkdaySettings.configuration(defaults: defaults)
        guard latest != configuration else { return }
        configuration = latest
        refresh()
    }

    private func refresh() {
        loadTask?.cancel()
        guard let month else { return }
        recompute(month: month, holidays: [])
        guard configuration.showCount || configuration.markHolidays,
              let region = configuration.regionCode else {
            holidayNames = [:]
            return
        }
        let year = calendar.component(.year, from: month)
        let provider = provider
        loadTask = Task { [weak self] in
            guard let holidays = try? await provider.holidays(region: region, year: year),
                  !Task.isCancelled, let self else { return }
            self.holidayNames = Dictionary(holidays.map { ($0.dateKey, $0.name) }, uniquingKeysWith: { first, _ in first })
            self.recompute(month: month, holidays: holidays)
        }
    }

    private func recompute(month: Date, holidays: [PublicHoliday]) {
        if holidays.isEmpty { holidayNames = [:] }
        summary = WorkdayCalculator.summary(
            forMonth: month,
            weekendWeekdays: configuration.weekendWeekdays,
            holidays: holidays,
            calendar: calendar
        )
    }
}
