import Foundation

/// What the app holds: reads and search straight from the store (never
/// waiting on sync), triggers into the coordinator, and a stream of
/// committed changes.
///
/// Later stages plug in here: an `IndexedCalendarProvider` reads
/// `occurrences`/`dayMarkers` and calls `ensure` for missing months;
/// search calls `search`; `.rangeCommitted` maps onto the app's
/// `.calendarEventsDidChange`.
public final class CalendarIndexService: Sendable {
    public let store: IndexStore
    public let coordinator: SyncCoordinator
    private let source: EventSnapshotSource
    private let broadcaster: IndexEventBroadcaster

    public init(store: IndexStore, source: EventSnapshotSource, policy: SyncPolicy = .default,
                clock: IndexClock = SystemIndexClock()) {
        let broadcaster = IndexEventBroadcaster()
        self.store = store
        self.source = source
        self.broadcaster = broadcaster
        self.coordinator = SyncCoordinator(store: store, source: source, policy: policy, clock: clock,
                                           broadcaster: broadcaster)
    }

    // MARK: - Lifecycle and triggers

    public func start() {
        Task { await coordinator.start() }
    }

    public func stop() {
        Task { await coordinator.stop() }
    }

    /// Calendar access was revoked: stop syncing and erase every event the
    /// index holds. `start()` refills it once access is back.
    public func revoke() async {
        await coordinator.revoke()
    }

    /// Calendar access as the system reports it now — never a stored
    /// value. Every read below checks it: a cache isn't a permission.
    public var authorization: SourceAuthorization { source.currentAuthorization() }

    public var isAuthorized: Bool { authorization.isAuthorized }

    /// The range on screen — refreshed first (P0).
    public func focus(_ visible: DateInterval) {
        Task { await coordinator.setFocus(visible) }
    }

    /// Fetches months of `range` that were never indexed, waiting briefly.
    @discardableResult
    public func ensure(_ range: DateInterval, calendars: [String]? = nil) async -> Bool {
        await coordinator.ensure(range, calendars: calendars)
    }

    /// The app changed events in these ranges (empty calendars = all).
    public func noteWrite(_ ranges: [DateInterval], calendars: [String] = []) {
        Task { await coordinator.noteWrite(ranges, calendars: calendars) }
    }

    /// Pauses or resumes filling the outer years; what's on screen keeps
    /// syncing either way.
    public func setPaused(_ paused: Bool) {
        Task { await coordinator.setPaused(paused) }
    }

    /// Erases the index and rebuilds it from the source.
    public func reindex() async {
        await coordinator.reindex()
    }

    /// Something changed, now (no debounce): inventory, then the visible
    /// and near months.
    public func noteChange() {
        Task { await coordinator.applyChange() }
    }

    public func noteLifecycle(_ event: SyncLifecycle) {
        Task { await coordinator.noteLifecycle(event) }
    }

    /// Each call returns an independent subscription.
    public func events() -> AsyncStream<IndexEvent> {
        broadcaster.subscribe()
    }

    // MARK: - Reads (milliseconds; safe from the main thread)

    public func occurrences(in interval: DateInterval) throws -> ReadResult<[IndexedOccurrence]> {
        try read(interval) { try store.occurrences(in: interval) }
    }

    public func dayMarkers(in interval: DateInterval) throws -> ReadResult<[DayMarker]> {
        try read(interval) { try store.dayMarkers(in: interval) }
    }

    public func search(_ request: SearchRequest, now: Date = Date()) throws -> ReadResult<[SearchHit]> {
        let authorization = self.authorization
        let refreshing = broadcaster.progress.isRefreshing
        let coverage = try request.interval.map { try store.coverageInfo(for: $0, isRefreshing: refreshing) }
            ?? CoverageInfo(missingMonths: [], oldestFetch: nil, isRefreshing: refreshing)
        guard authorization.isAuthorized else {
            return ReadResult(value: [], coverage: coverage, authorization: authorization)
        }
        return ReadResult(value: try store.search(request, now: now), coverage: coverage, authorization: authorization)
    }

    /// Every match in date order, ids and starts only.
    public func searchMatches(_ request: SearchRequest) throws -> [SearchMatch] {
        guard isAuthorized else { return [] }
        return try store.searchMatches(request)
    }

    /// The best text matches first, with titles (no payloads).
    public func searchRanked(_ request: SearchRequest, now: Date = Date(), upcomingFrom: Date? = nil) throws -> [RankedMatch] {
        guard isAuthorized else { return [] }
        return try store.searchRanked(request, now: now, upcomingFrom: upcomingFrom)
    }

    /// The calendars EventKit last listed (titles, colors).
    public func activeCalendars() throws -> [CalendarSnapshot] {
        guard isAuthorized else { return [] }
        return try store.activeCalendars()
    }

    /// Full occurrences for the ids a view shows.
    public func occurrences(ids: [Int64]) throws -> [IndexedOccurrence] {
        guard isAuthorized else { return [] }
        return try store.occurrences(ids: ids)
    }

    /// Unauthorized: nothing is served, whatever the store still holds.
    private func read<T: Sendable>(_ interval: DateInterval, _ body: () throws -> [T]) throws -> ReadResult<[T]> {
        let authorization = self.authorization
        let coverage = try store.coverageInfo(for: interval, isRefreshing: broadcaster.progress.isRefreshing)
        guard authorization.isAuthorized else {
            return ReadResult(value: [], coverage: coverage, authorization: authorization)
        }
        return ReadResult(value: try body(), coverage: coverage, authorization: authorization)
    }
}
