import Foundation
import Observation
import Domain

/// The Command Window's month grid's events, by day — app-wide (the
/// window's views come and go; this doesn't), so the grid opens filled.
///
/// The month shown and the ones either side are kept ready: after showing a
/// month its neighbours load in the background, so moving to one (the
/// agenda scrolling past a month's end, ← / →) swaps its chips in at once.
/// A calendar or visibility change drops what's held and refetches the
/// month shown, its chips staying up until the new ones arrive. Never
/// fetched for a selection change; at most three months held.
@MainActor
@Observable
package final class MonthEventsStore {
    private(set) var eventsByDay: [Date: [AgendaEventModel]] = [:]
    @ObservationIgnored private let dataProvider: CalendarDataProviding
    @ObservationIgnored private let calendar: Calendar
    /// Month start → its days' events (grid overflow days included).
    @ObservationIgnored private var months: [Date: [Date: [AgendaEventModel]]] = [:]
    @ObservationIgnored private var shownMonth: Date?
    /// Bumped by every change: a load started before one is stale.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored nonisolated(unsafe) private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let notificationCenter: NotificationCenter

    package init(dataProvider: CalendarDataProviding, calendar: Calendar = .autoupdatingCurrent,
                 notificationCenter: NotificationCenter = .default) {
        self.dataProvider = dataProvider
        self.calendar = calendar
        self.notificationCenter = notificationCenter
        observers = [Notification.Name.calendarEventsDidChange, .sourceVisibilityDidChange].map { name in
            notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.calendarDidChange() }
            }
        }
    }

    deinit {
        observers.forEach(notificationCenter.removeObserver)
    }

    package func events(on date: Date) -> [AgendaEventModel] {
        eventsByDay[calendar.startOfDay(for: date)] ?? []
    }

    /// Shows `month`'s events — at once when it's ready, else once loaded —
    /// then readies its neighbours.
    package func show(month: Date) async {
        guard let start = calendar.dateInterval(of: .month, for: month)?.start else { return }
        shownMonth = start
        if let ready = months[start] {
            eventsByDay = ready
        } else {
            guard let loaded = await load(start), shownMonth == start else { return }
            eventsByDay = loaded
        }
        for offset in [1, -1] {
            guard let neighbour = calendar.date(byAdding: .month, value: offset, to: start),
                  months[neighbour] == nil else { continue }
            _ = await load(neighbour)
            guard shownMonth == start else { return }
        }
        // The shown month and its two neighbours only.
        let kept = Set([-1, 0, 1].compactMap { calendar.date(byAdding: .month, value: $0, to: start) })
        months = months.filter { kept.contains($0.key) }
    }

    /// The calendar changed: nothing held is current. The month shown is
    /// fetched again (its chips stay up meanwhile); neighbours on demand.
    func calendarDidChange() {
        generation += 1
        months = [:]
        guard let shownMonth else { return }
        Task { [weak self] in
            guard let self, let loaded = await self.load(shownMonth), self.shownMonth == shownMonth else { return }
            self.eventsByDay = loaded
        }
    }

    /// The month's days and the week either side (whatever the grid's week
    /// start, its overflow days are covered), held under the month's start.
    private func load(_ start: Date) async -> [Date: [AgendaEventModel]]? {
        let loadedGeneration = generation
        guard let end = calendar.date(byAdding: .month, value: 1, to: start),
              let from = calendar.date(byAdding: .day, value: -7, to: start),
              let to = calendar.date(byAdding: .day, value: 14, to: end) else { return nil }
        let sections = await dataProvider.agendaSections(in: DateInterval(start: from, end: to), calendar: calendar)
        // A calendar change meanwhile: this answer is stale.
        guard generation == loadedGeneration else { return nil }
        let days = Dictionary(sections.map { (calendar.startOfDay(for: $0.date), $0.events) },
                              uniquingKeysWith: { first, _ in first })
        months[start] = days
        return days
    }
}
