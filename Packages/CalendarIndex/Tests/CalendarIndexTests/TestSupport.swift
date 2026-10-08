import Foundation
import GRDB
import XCTest
@testable import CalendarIndex

func date(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: iso)!
}

func month(_ iso: String) -> Date {
    MonthGrid.month(containing: date(iso))
}

func event(_ item: String, calendar: String = "A", start: String, hours: Double = 1, title: String = "Event",
           external: String? = nil, recurring: Bool = false, occurrence: String? = nil, allDay: Bool = false,
           notes: String? = nil, location: String? = nil, attendees: [AttendeeSnapshot] = [],
           participation: ParticipationStatus? = nil) -> OccurrenceSnapshot {
    let begin = date(start)
    return OccurrenceSnapshot(
        calendarIdentifier: calendar, eventIdentifier: "ev-\(item)", calendarItemIdentifier: item,
        externalIdentifier: external, occurrenceDate: recurring ? (occurrence.map(date) ?? begin) : nil,
        start: begin, end: begin.addingTimeInterval(hours * 3600), isAllDay: allDay,
        title: title, location: location, notes: notes, attendees: attendees,
        participation: participation, isRecurring: recurring)
}

func makeStore(file: String = "index.sqlite", options: IndexStore.Options? = nil) throws -> IndexStore {
    try IndexStore.open(at: temporaryDirectory().appendingPathComponent(file), options: options ?? testOptions())
}

func testOptions() -> IndexStore.Options {
    var options = IndexStore.Options()
    options.eraseOnSchemaChange = false
    options.keyCalendar = utcCalendar
    return options
}

let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("CalendarIndexTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

extension IndexStore {
    /// Every row, including soft-deleted and inactive ones.
    func allRows() throws -> [(id: Int64, key: String, title: String, missing: Bool)] {
        try pool.read { db in
            try Row.fetchAll(db, sql: "SELECT id, occurrence_key, title, missing_since FROM occurrence ORDER BY id").map {
                ($0[0], $0[1], $0[2], ($0[3] as Double?) != nil)
            }
        }
    }

    func totalChanges() throws -> Int {
        try pool.write { $0.totalChangesCount }
    }
}

final class TestClock: IndexClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ now: Date) {
        current = now
    }

    func now() -> Date { lock.withLock { current } }

    func advance(by seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }

    /// Sleeping advances this clock instead of waiting: pacing gaps are
    /// simulated, and tests can read how much time "passed".
    func sleep(for duration: Duration) async throws {
        advance(by: duration.timeInterval)
        await Task.yield()
        try Task.checkCancellation()
    }
}

/// A scripted EventKit: calendars, events, authorization, failures, and a
/// gate that holds a fetch open (its result is taken when it *starts*, as
/// EventKit's would be).
final class FakeSnapshotSource: EventSnapshotSource, @unchecked Sendable {
    struct Fetch: Equatable {
        var range: DateInterval
        var calendars: [String]
        /// The test clock's time when the fetch started (if one is attached).
        var at: Date?
        var months: [Date] { MonthGrid.months(overlapping: range) }
    }

    private let lock = NSLock()
    private var _calendars: [CalendarSnapshot]
    private var _events: [OccurrenceSnapshot]
    private var _authorization: SourceAuthorization = .authorized
    private var _fetches: [Fetch] = []
    private var _failingMonths: Set<Date> = []
    private var _holdNext = false
    private var _held: CheckedContinuation<Void, Never>?
    /// When set, each fetch "takes" `fetchSeconds` on this clock.
    var clock: TestClock?
    var fetchSeconds: TimeInterval = 0
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init(calendars: [String] = ["A"], events: [OccurrenceSnapshot] = []) {
        _calendars = calendars.map { CalendarSnapshot(identifier: $0, title: $0) }
        _events = events
        (stream, continuation) = AsyncStream.makeStream(of: Void.self)
    }

    var events: [OccurrenceSnapshot] {
        get { lock.withLock { _events } }
        set { lock.withLock { _events = newValue } }
    }

    var calendarIdentifiers: [String] {
        get { lock.withLock { _calendars.map(\.identifier) } }
        set { lock.withLock { _calendars = newValue.map { CalendarSnapshot(identifier: $0, title: $0) } } }
    }

    var authorizationStatus: SourceAuthorization {
        get { lock.withLock { _authorization } }
        set { lock.withLock { _authorization = newValue } }
    }

    var fetches: [Fetch] { lock.withLock { _fetches } }
    var fetchedMonths: [Date] { fetches.flatMap(\.months) }

    func resetLog() { lock.withLock { _fetches = [] } }

    func failMonths(_ months: Set<Date>) { lock.withLock { _failingMonths = months } }

    func holdNextFetch() { lock.withLock { _holdNext = true } }

    func waitUntilHeld() async {
        while lock.withLock({ _held == nil }) { try? await Task.sleep(for: .milliseconds(1)) }
    }

    func release() {
        let held = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            defer { _held = nil }
            return _held
        }
        held?.resume()
    }

    func signalChange() { continuation.yield() }

    func authorization() async -> SourceAuthorization { authorizationStatus }

    func currentAuthorization() -> SourceAuthorization { authorizationStatus }

    func calendars() async throws -> [CalendarSnapshot] {
        guard authorizationStatus.isAuthorized else { throw SourceError.unauthorized }
        return lock.withLock { _calendars }
    }

    func occurrences(in range: DateInterval, calendars ids: [String]) async throws -> SourceFetch {
        // Checked when the query starts, as EventKit's is: a fetch held
        // open across a revocation still returns what it read.
        guard authorizationStatus.isAuthorized else { throw SourceError.unauthorized }
        let (result, hold, fails): (SourceFetch, Bool, Bool) = lock.withLock {
            _fetches.append(Fetch(range: range, calendars: ids, at: clock?.now()))
            clock?.advance(by: fetchSeconds)
            let known = Set(_calendars.map(\.identifier)).intersection(ids)
            let snapshots = _events.filter {
                known.contains($0.calendarIdentifier) && $0.start < range.end && ($0.end > range.start || $0.start >= range.start)
            }
            let hold = _holdNext
            _holdNext = false
            let fails = !_failingMonths.isDisjoint(with: MonthGrid.months(overlapping: range))
            return (SourceFetch(snapshots: snapshots, calendars: known), hold, fails)
        }
        if hold {
            await withCheckedContinuation { continuation in
                lock.withLock { _held = continuation }
            }
        }
        if fails { throw URLError(.timedOut) }
        if result.calendars.isEmpty { throw SourceError.calendarsUnavailable }
        return result
    }

    func changes() -> AsyncStream<Void> { stream }
}

/// Small horizons so a full fill is a handful of months.
func smallPolicy(monthsPerQuery: Int = 1) -> SyncPolicy {
    var policy = SyncPolicy()
    policy.visiblePaddingMonths = 0
    policy.nearMonths = 1
    policy.midMonths = 2
    policy.farMonths = 3
    policy.maxMonthsPerQuery = monthsPerQuery
    return policy
}
