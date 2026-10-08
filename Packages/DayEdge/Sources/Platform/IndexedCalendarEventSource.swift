import CalendarIndex
import Foundation
import Domain

/// The app's event source: the local calendar index
/// (`Packages/CalendarIndex`), a mirror of EventKit kept fresh in the
/// background — milliseconds per read, no in-memory cache. Writes still go
/// to EventKit directly (`EventKitEventEditor`) and announce their scope.
///
/// Months not indexed yet: the agenda (async) waits briefly for them
/// (`CalendarIndexService.ensure`, bounded); synchronous reads (month grid,
/// day preview) return what's there and ask for the rest, and the views
/// refresh on `.calendarEventsDidChange` when it lands. That notification
/// is posted after index commits — never before the data is readable.
package final class IndexedCalendarEventSource: CalendarEventSource, @unchecked Sendable {
    private let service: CalendarIndexService
    private let lock = NSLock()
    /// Months already asked for by a synchronous read, so a redraw doesn't
    /// queue the same `ensure` again.
    private var requestedMonths: Set<Date> = []
    /// Months any view has read. A commit elsewhere (the background fill
    /// of other years) changes nothing on screen, so it isn't announced.
    private var watchedMonths: Set<Date> = []
    private var eventsTask: Task<Void, Never>?
    private var writeObserver: NSObjectProtocol?
    private var postScheduled = false

    /// How long commits are gathered into one `.calendarEventsDidChange`
    /// (a fill commits many months in a row).
    private static let changeCoalescing: TimeInterval = 0.1

    package init(service: CalendarIndexService) {
        self.service = service
        let events = service.events()
        eventsTask = Task { [weak self] in
            for await event in events {
                switch event {
                case .rangeCommitted(_, let interval):
                    guard let self, self.isWatched(interval) else { continue }
                    self.scheduleChangePost()
                case .calendarsChanged, .authorizationChanged, .reset:
                    self?.scheduleChangePost()
                case .progress, .nearReady:
                    continue
                }
            }
        }
        // The app's own edits: refetch exactly what they touched, ahead of
        // everything else; an edit without a scope refreshes the near months.
        writeObserver = NotificationCenter.default.addObserver(forName: .calendarEventsWritten, object: nil,
                                                               queue: .main) { [service] note in
            if let scope = note.userInfo?[CalendarWriteScope.userInfoKey] as? CalendarWriteScope {
                service.noteWrite(scope.ranges, calendars: Array(scope.calendarIdentifiers))
            } else {
                service.noteChange()
            }
        }
    }

    deinit {
        eventsTask?.cancel()
        if let writeObserver { NotificationCenter.default.removeObserver(writeObserver) }
    }

    package var isAuthorized: Bool { service.isAuthorized }

    // MARK: - Reads

    package func markersByDaySync(in window: DateInterval, calendar: Calendar) -> [Date: [SourceMarker]] {
        let read = readWindow(for: window, calendar: calendar)
        service.focus(read)
        guard let result = try? service.dayMarkers(in: read) else { return [:] }
        requestMissingMonths(result.coverage, in: read)
        let colors = calendarColors()
        let items = result.value.map { marker in
            Bucketed(id: marker.occurrenceID, startDate: marker.start, endDate: marker.end, value: SourceMarker(
                calendarIdentifier: marker.calendarIdentifier,
                startDate: marker.start,
                isDeclinedByUser: Self.isDeclinedByUser(participation: marker.participation, status: marker.status),
                dotTint: colors[marker.calendarIdentifier] ?? .placeholder
            ))
        }
        return bucket(items, window: window, calendar: calendar)
    }

    package func eventsByDaySync(in window: DateInterval, calendar: Calendar) -> [Date: [SourceEvent]] {
        let read = readWindow(for: window, calendar: calendar)
        guard let result = try? service.occurrences(in: read) else { return [:] }
        requestMissingMonths(result.coverage, in: read)
        return bucket(result.value.map(Self.bucketed), window: window, calendar: calendar)
    }

    package func eventsByDay(in window: DateInterval, calendar: Calendar) async -> [Date: [SourceEvent]] {
        let read = readWindow(for: window, calendar: calendar)
        service.focus(read)
        guard var result = try? service.occurrences(in: read) else { return [:] }
        // `ensure` checks access itself; only a known denial skips it (a new
        // index doesn't know its permission until the first check).
        if !result.coverage.isComplete, result.authorization != .denied {
            await service.ensure(read)
            if let fresh = try? service.occurrences(in: read) { result = fresh }
        }
        return bucket(result.value.map(Self.bucketed), window: window, calendar: calendar)
    }

    package func searchMatches(_ request: SearchRequest) -> [CalendarIndex.SearchMatch] {
        (try? service.searchMatches(request)) ?? []
    }

    package func searchRanked(_ request: SearchRequest, now: Date) -> [CalendarIndex.RankedMatch] {
        // Upcoming from the start of today, as the Search view opens there.
        let today = Calendar.autoupdatingCurrent.startOfDay(for: now)
        return (try? service.searchRanked(request, now: now, upcomingFrom: today)) ?? []
    }

    package func events(matchIDs: [Int64]) -> [Int64: SourceEvent] {
        let occurrences = (try? service.occurrences(ids: matchIDs)) ?? []
        return Dictionary(occurrences.map { ($0.id, Self.bucketed($0).value) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Helpers

    /// Whole days: the read runs to the end of the window's last day, so
    /// that day's list is complete (the provider includes it, as the
    /// EventKit source's padded cache always did).
    private func readWindow(for window: DateInterval, calendar: Calendar) -> DateInterval {
        let start = calendar.startOfDay(for: window.start)
        let lastDay = calendar.startOfDay(for: window.end)
        let end = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? window.end
        let read = DateInterval(start: start, end: max(start, end))
        let months = MonthGrid.months(overlapping: read)
        lock.withLock { watchedMonths.formUnion(months) }
        return read
    }

    private func isWatched(_ interval: DateInterval) -> Bool {
        let months = Set(MonthGrid.months(overlapping: interval))
        return lock.withLock { !watchedMonths.isDisjoint(with: months) }
    }

    private func bucket<Value>(_ items: [Bucketed<Value>], window: DateInterval, calendar: Calendar) -> [Date: [Value]] {
        DayBuckets.index(items, calendar: calendar, windowStart: window.start, windowEnd: window.end, mergingInto: [:])
            .mapValues { $0.map(\.value) }
    }

    private static func bucketed(_ occurrence: IndexedOccurrence) -> Bucketed<SourceEvent> {
        let snapshot = occurrence.snapshot
        let calendar = occurrence.calendar
        let marker = SourceMarker(
            calendarIdentifier: snapshot.calendarIdentifier,
            startDate: snapshot.start,
            isDeclinedByUser: isDeclinedByUser(participation: snapshot.participation, status: snapshot.status),
            dotTint: CalendarEventMapper.tint(calendar.color)
        )
        return Bucketed(id: occurrence.id, startDate: snapshot.start, endDate: snapshot.end, value: SourceEvent(
            marker: marker,
            makeModel: { CalendarEventMapper.agendaEventModel(from: snapshot, calendar: calendar) }
        ))
    }

    /// `DeclinedEventFilter` on stored values (an unknown status reads as
    /// not cancelled).
    package static func isDeclinedByUser(participation: ParticipationStatus?, status: OccurrenceSnapshot.Status?) -> Bool {
        DeclinedEventFilter.isDeclinedByUser(declinedByMe: participation == .declined, isCanceledByOrganizer: status == .canceled)
    }

    private func calendarColors() -> [String: RGBAColor] {
        let calendars = (try? service.activeCalendars()) ?? []
        return Dictionary(calendars.map { ($0.identifier, CalendarEventMapper.tint($0.color)) },
                          uniquingKeysWith: { first, _ in first })
    }

    /// A synchronous read can't wait: ask for the missing months once; the
    /// views refresh when they're committed.
    private func requestMissingMonths(_ coverage: CoverageInfo, in read: DateInterval) {
        guard !coverage.isComplete, service.authorization != .denied else { return }
        let fresh = lock.withLock { () -> Bool in
            let new = Set(coverage.missingMonths).subtracting(requestedMonths)
            requestedMonths.formUnion(new)
            return !new.isEmpty
        }
        guard fresh else { return }
        let service = service
        Task { [weak self] in
            await service.ensure(read)
            guard let self else { return }
            self.lock.withLock { self.requestedMonths.subtract(coverage.missingMonths) }
        }
    }

    private func scheduleChangePost() {
        let shouldSchedule = lock.withLock { () -> Bool in
            guard !postScheduled else { return false }
            postScheduled = true
            return true
        }
        guard shouldSchedule else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.changeCoalescing) { [weak self] in
            guard let self else { return }
            self.lock.withLock { self.postScheduled = false }
            NotificationCenter.default.post(name: .calendarEventsDidChange, object: nil)
        }
    }
}

/// Anything placed on days by `DayBuckets`.
private struct Bucketed<Value>: EventSpanning {
    let id: AnyHashable
    let startDate: Date
    let endDate: Date
    let value: Value

    init(id: Int64, startDate: Date, endDate: Date, value: Value) {
        self.id = AnyHashable(id)
        self.startDate = startDate
        self.endDate = endDate
        self.value = value
    }
}
