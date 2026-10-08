import CalendarIndex
import Foundation
import Domain

/// Everything the app shapes events into — the month grid, agenda
/// sections, a single day — over whichever `CalendarEventSource` is
/// plugged in (see `AppConfiguration.calendarBackend`). Conforms to the
/// same `CalendarDataProviding` protocol `MockCalendarDataProvider` does,
/// so `CalendarViewModel` and every view above it are unaffected by which
/// one is plugged in.
///
/// Orchestration only: fetching, caching and `EKEvent` → model mapping
/// belong to the source. This type's own job is: ask the source, filter
/// by calendar visibility and declined state, and project into
/// `DayCellModel`/`AgendaDaySection`.
///
/// Not fully async: `days(for:selectedDate:calendar:)`/
/// `events(for:calendar:)` are synchronous protocol requirements, so a
/// source's cache miss can still block the calling (main) thread.
/// Eliminating that would mean making `CalendarDataProviding` itself
/// async, which ripples into `CalendarViewModel` and every view reading
/// `viewModel.days` directly in `body` — a separate, larger change.
package final class CalendarProvider: CalendarDataProviding {
    private let source: CalendarEventSource
    private let visibilityStore: SourceVisibilityStore
    private let maxDotsPerDay: Int
    private let showsDeclined: () -> Bool

    package init(source: CalendarEventSource,
                 visibilityStore: SourceVisibilityStore,
                 maxDotsPerDay: Int = AppConfiguration.maxDotsPerDay,
                 showsDeclined: @escaping () -> Bool = { GeneralSettings.showsDeclined() }) {
        self.source = source
        self.visibilityStore = visibilityStore
        self.maxDotsPerDay = maxDotsPerDay
        self.showsDeclined = showsDeclined
    }

    package var isAuthorized: Bool { source.isAuthorized }

    /// Read on the caller's own thread (always main, today) and captured
    /// as a plain value/closure *before* anything crosses onto a source's
    /// background queue — so nothing ever touches the live `@Observable`
    /// `SourceVisibilityStore` from off the main thread.
    private func visibilitySnapshot() -> (SourceMarker) -> Bool {
        let excluded = visibilityStore.excludedIDs
        let hidden = visibilityStore.hiddenIDs
        let showsDeclined = showsDeclined()
        return { event in
            guard !excluded.contains(event.calendarIdentifier), !hidden.contains(event.calendarIdentifier) else { return false }
            return showsDeclined || !event.isDeclinedByUser
        }
    }

    package func days(for monthAnchor: Date, selectedDate: Date, calendar: Calendar) -> [DayCellModel] {
        guard source.isAuthorized,
              let monthInterval = calendar.dateInterval(of: .month, for: monthAnchor) else { return [] }

        let firstOfMonth = monthInterval.start
        let firstWeekdayOffset = (calendar.component(.weekday, from: firstOfMonth) - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -firstWeekdayOffset, to: firstOfMonth),
              let gridEnd = calendar.date(byAdding: .day, value: 42, to: gridStart) else { return [] }

        let today = calendar.startOfDay(for: Date())
        let isVisible = visibilitySnapshot()
        let markersByDay = source.markersByDaySync(in: DateInterval(start: gridStart, end: gridEnd), calendar: calendar)

        return (0..<42).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else { return nil }
            let dayStart = calendar.startOfDay(for: date)
            let weekday = calendar.component(.weekday, from: date)

            // Always filled here regardless of acceptance status — at
            // this tiny size the dashed/unfilled treatment (used for
            // the same distinction in the agenda list, where there's
            // room for it) is nearly invisible, so a solid dot in the
            // calendar's own color reads far better for "something's
            // on this day." Keep one item beyond the visible-dot limit
            // so `EventDotsView` can distinguish exactly four events
            // from overflow and replace slot four with its `+` marker.
            let dots = (markersByDay[dayStart] ?? [])
                .filter(isVisible)
                .prefix(maxDotsPerDay + 1)
                .map { DotStyle(tint: $0.dotTint, isFilled: true) }

            return DayCellModel(
                date: date,
                dayNumber: calendar.component(.day, from: date),
                isCurrentMonth: calendar.isDate(date, equalTo: monthAnchor, toGranularity: .month),
                isToday: calendar.isDate(date, inSameDayAs: today),
                isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                isWeekend: weekday == 1 || weekday == 7,
                dots: Array(dots)
            )
        }
    }

    /// Answers exactly the requested `range` — no "always include today,"
    /// no window-widening policy. That belongs to `AgendaSectionStore`,
    /// which is the one place that knows about "the current window" at
    /// all; this method just runs a bounded query.
    package func agendaSections(in range: DateInterval, calendar: Calendar) async -> [AgendaDaySection] {
        let isVisible = visibilitySnapshot()
        let eventsByDay = await source.eventsByDay(in: range, calendar: calendar)

        let rangeStart = calendar.startOfDay(for: range.start)
        let rangeEnd = calendar.startOfDay(for: range.end)
        let days = eventsByDay.keys.filter { $0 >= rangeStart && $0 <= rangeEnd }

        return days.sorted().map { day -> AgendaDaySection in
            let dayEvents = (eventsByDay[day] ?? [])
                .filter { isVisible($0.marker) }
            return AgendaDaySection(
                date: day,
                events: Self.ordered(dayEvents.map { $0.makeModel() }),
                isToday: calendar.isDateInToday(day)
            )
        }
    }

    package func events(for date: Date, calendar: Calendar) -> [AgendaEventModel] {
        let day = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) else { return [] }

        let isVisible = visibilitySnapshot()
        let eventsByDay = source.eventsByDaySync(in: DateInterval(start: day, end: dayEnd), calendar: calendar)
        let events = (eventsByDay[day] ?? [])
            .filter { isVisible($0.marker) }
            .map { $0.makeModel() }
        return Self.ordered(events)
    }

    @MainActor
    package func searchEventMatches(_ query: SearchQueryParts) async -> [Domain.SearchMatch] {
        let request = searchRequest(query, limit: 0)
        let source = self.source
        return await Task.detached(priority: .userInitiated) { source.searchMatches(request).map(Domain.SearchMatch.init) }.value
    }

    @MainActor
    package func searchRankedEvents(_ query: SearchQueryParts, limit: Int) async -> [Domain.RankedMatch] {
        let request = searchRequest(query, limit: limit)
        let source = self.source
        return await Task.detached(priority: .userInitiated) { source.searchRanked(request, now: Date()).map(Domain.RankedMatch.init) }.value
    }

    /// A search as the index takes it, with the agenda's visibility
    /// (hidden and excluded calendars) and declined rule — read here, on
    /// the main actor.
    @MainActor
    private func searchRequest(_ query: SearchQueryParts, limit: Int) -> SearchRequest {
        SearchRequest(text: query.text, titleText: query.subject, organizer: query.organizer, attendee: query.attendee,
                      organizedByMe: query.organizedByMe, interval: query.interval, excludedCalendars: visibilityStore.excludedIDs.union(visibilityStore.hiddenIDs),
                      includesDeclined: showsDeclined(), limit: limit)
    }

    package func searchEvents(ids: [Int64]) async -> [Int64: AgendaEventModel] {
        let source = self.source
        return await Task.detached(priority: .userInitiated) {
            source.events(matchIDs: ids).mapValues { $0.makeModel() }
        }.value
    }

    /// By start; same-start ties by title, then id — a fixed order, not
    /// whatever order a source happened to return them in.
    package static func ordered(_ events: [AgendaEventModel]) -> [AgendaEventModel] {
        events.sorted {
            let (a, b) = ($0.startDate ?? .distantPast, $1.startDate ?? .distantPast)
            if a != b { return a < b }
            if $0.title != $1.title { return $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            return $0.id < $1.id
        }
    }
}
