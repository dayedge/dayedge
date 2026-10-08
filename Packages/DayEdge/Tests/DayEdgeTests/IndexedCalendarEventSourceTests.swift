import CalendarIndex
import XCTest
@testable import Shell
@testable import Domain
@testable import Platform

/// `IndexedCalendarEventSource` over a real (temporary) index fed by a
/// scripted source — no EventKit.
final class IndexedCalendarEventSourceTests: XCTestCase {
    private var calendar: Calendar!
    private var fake: ScriptedSnapshotSource!
    private var service: CalendarIndexService!
    private var source: IndexedCalendarEventSource!

    override func setUpWithError() throws {
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        fake = ScriptedSnapshotSource()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("IndexedSourceTests-\(UUID().uuidString)/index.sqlite")
        var options = IndexStore.Options()
        options.eraseOnSchemaChange = false
        var policy = SyncPolicy()
        policy.farMonths = 2
        policy.midMonths = 1
        policy.nearMonths = 1
        service = CalendarIndexService(store: try IndexStore.open(at: url, options: options), source: fake, policy: policy)
        source = IndexedCalendarEventSource(service: service)
    }

    private func at(_ day: Int, month: Int = Calendar.current.component(.month, from: Date()), hour: Int = 9) -> Date {
        let now = calendar.dateComponents([.year], from: Date())
        return calendar.date(from: DateComponents(year: now.year, month: month, day: day, hour: hour))!
    }

    private func thisMonth() -> DateInterval { calendar.dateInterval(of: .month, for: Date())! }

    func testMonthGridComesFromMarkersWithColorsSpansAndDeclinedRule() async throws {
        let month = Calendar.current.component(.month, from: Date())
        fake.events = [
            fake.event("trip", start: at(3, month: month), hours: 24 * 3, title: "Trip"),
            fake.event("no", start: at(10, month: month), title: "Declined", participation: .declined),
            fake.event("off", start: at(11, month: month), title: "Cancelled + declined", participation: .declined, status: .canceled),
        ]
        await service.coordinator.runUntilIdle()

        let byDay = source.markersByDaySync(in: thisMonth(), calendar: calendar)
        for day in 3...5 {
            XCTAssertEqual(byDay[calendar.startOfDay(for: at(day, month: month))]?.count, 1, "trip on day \(day)")
        }
        XCTAssertEqual(byDay[calendar.startOfDay(for: at(10, month: month))]?.first?.isDeclinedByUser, true)
        XCTAssertEqual(byDay[calendar.startOfDay(for: at(11, month: month))]?.first?.isDeclinedByUser, false,
                       "an organizer cancellation isn't a decline")
        XCTAssertEqual(byDay.values.first!.first!.dotTint, RGBAColor(red: 0.2, green: 0.4, blue: 0.8))
    }

    func testAgendaWaitsForMonthsNotYetIndexed() async throws {
        fake.events = [fake.event("a", start: Date().addingTimeInterval(3600), title: "Soon")]
        let window = DateInterval(start: calendar.startOfDay(for: Date()), duration: 2 * 86400)
        // Nothing indexed and the coordinator not started: the read fetches
        // just these months and returns their events.
        let byDay = await source.eventsByDay(in: window, calendar: calendar)
        XCTAssertEqual(byDay.values.flatMap { $0 }.map { $0.makeModel().title }, ["Soon"])
        XCTAssertEqual(Set(fake.fetchedMonths), Set(MonthGrid.months(overlapping: window)))
    }

    func testSyncReadReturnsAtOnceAndPostsChangeWhenTheMonthLands() async throws {
        fake.events = [fake.event("a", start: Date().addingTimeInterval(3600), title: "Soon")]
        let changed = expectation(forNotification: .calendarEventsDidChange, object: nil)
        let first = source.markersByDaySync(in: thisMonth(), calendar: calendar)
        XCTAssertTrue(first.isEmpty, "nothing indexed yet — returns at once")
        await fulfillment(of: [changed], timeout: 5)
        XCTAssertEqual(source.markersByDaySync(in: thisMonth(), calendar: calendar).values.flatMap { $0 }.count, 1)
    }

    func testUnauthorizedReadsNothing() async throws {
        fake.events = [fake.event("a", start: Date().addingTimeInterval(3600), title: "Private")]
        await service.coordinator.runUntilIdle()
        XCTAssertTrue(source.isAuthorized)
        fake.authorizationStatus = .denied
        await service.coordinator.noteLifecycle(.activate)
        await service.coordinator.runUntilIdle()
        XCTAssertFalse(source.isAuthorized)
        XCTAssertTrue(source.markersByDaySync(in: thisMonth(), calendar: calendar).isEmpty)
        let agenda = await source.eventsByDay(in: thisMonth(), calendar: calendar)
        XCTAssertTrue(agenda.isEmpty)
    }

    func testOwnWritesRefreshTheNearMonths() async throws {
        await service.coordinator.runUntilIdle()
        fake.resetLog()
        NotificationCenter.default.post(name: .calendarEventsWritten, object: nil)
        try await Task.sleep(for: .milliseconds(100))
        await service.coordinator.runUntilIdle()
        XCTAssertTrue(fake.fetchedMonths.contains(MonthGrid.month(containing: Date())))
    }
}

/// A scripted `EventSnapshotSource` for app-side tests.
final class ScriptedSnapshotSource: EventSnapshotSource, @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [OccurrenceSnapshot] = []
    private var _authorization: SourceAuthorization = .authorized
    private var _fetched: [Date] = []

    var events: [OccurrenceSnapshot] {
        get { lock.withLock { _events } }
        set { lock.withLock { _events = newValue } }
    }

    var authorizationStatus: SourceAuthorization {
        get { lock.withLock { _authorization } }
        set { lock.withLock { _authorization = newValue } }
    }

    var fetchedMonths: [Date] { lock.withLock { _fetched } }
    func resetLog() { lock.withLock { _fetched = [] } }

    func event(_ item: String, start: Date, hours: Double = 1, title: String,
               participation: ParticipationStatus? = nil, status: OccurrenceSnapshot.Status = .confirmed) -> OccurrenceSnapshot {
        OccurrenceSnapshot(calendarIdentifier: "work", eventIdentifier: "ev-\(item)", calendarItemIdentifier: item,
                           externalIdentifier: "UID-\(item)", occurrenceDate: start, start: start,
                           end: start.addingTimeInterval(hours * 3600), title: title, status: status,
                           participation: participation)
    }

    func authorization() async -> SourceAuthorization { authorizationStatus }
    func currentAuthorization() -> SourceAuthorization { authorizationStatus }

    func calendars() async throws -> [CalendarSnapshot] {
        guard authorizationStatus.isAuthorized else { throw SourceError.unauthorized }
        return [CalendarSnapshot(identifier: "work", title: "Work", color: .init(red: 0.2, green: 0.4, blue: 0.8))]
    }

    func occurrences(in range: DateInterval, calendars: [String]) async throws -> SourceFetch {
        guard authorizationStatus.isAuthorized else { throw SourceError.unauthorized }
        return lock.withLock {
            _fetched += MonthGrid.months(overlapping: range)
            let snapshots = _events.filter { $0.start < range.end && $0.end > range.start }
            return SourceFetch(snapshots: snapshots, calendars: ["work"])
        }
    }

    func changes() -> AsyncStream<Void> { AsyncStream { _ in } }
}

final class EventAttendeeIdentityTests: XCTestCase {
    func testSamePersonKeepsTheSameIDAcrossReloads() {
        let first = EventAttendee(name: "Anna", status: .accepted, email: "Anna@Example.com")
        let reloaded = EventAttendee(name: "Anna", status: .accepted, email: "anna@example.com")
        XCTAssertEqual(first.id, reloaded.id)
        XCTAssertEqual(EventAttendee(name: "Bob", status: .pending).id, EventAttendee(name: "Bob", status: .pending).id)
    }

    func testRepeatedPeopleGetUniqueIDs() {
        let list = EventAttendee.uniquingIDs([EventAttendee(name: "Unknown", status: .unknown),
                                              EventAttendee(name: "Unknown", status: .unknown),
                                              EventAttendee(name: "Cara", status: .accepted)])
        XCTAssertEqual(list.map(\.id), ["name:Unknown", "name:Unknown#2", "name:Cara"])
    }
}

extension IndexedCalendarEventSourceTests {
    func testCommitsOutsideWatchedMonthsAreNotAnnounced() async throws {
        // Read only this month, then index a far-away one.
        _ = source.markersByDaySync(in: thisMonth(), calendar: calendar)
        try await Task.sleep(for: .milliseconds(500))
        let far = MonthGrid.month(MonthGrid.month(containing: Date()), adding: 2)
        fake.events = [fake.event("far", start: far.addingTimeInterval(86400 * 3), title: "Later")]
        let quiet = expectation(forNotification: .calendarEventsDidChange, object: nil)
        quiet.isInverted = true
        await service.coordinator.runUntilIdle()
        await fulfillment(of: [quiet], timeout: 1)
    }
}

final class CalendarWriteScopeTests: XCTestCase {
    private let nine = Date(timeIntervalSince1970: 1_791_000_000)

    func testMoveCoversOldAndNewTimesAndBothCalendars() {
        let scope = CalendarWriteScope.write(before: ("work", nine, nine.addingTimeInterval(3600)),
                                             after: ("home", nine.addingTimeInterval(86400 * 40), nine.addingTimeInterval(86400 * 40 + 3600)),
                                             throughFuture: false)
        XCTAssertEqual(scope.calendarIdentifiers, ["work", "home"])
        XCTAssertEqual(scope.ranges.map(\.start), [nine, nine.addingTimeInterval(86400 * 40)])
    }

    func testFutureEventsRunFromTheEarlierStartOn() {
        let scope = CalendarWriteScope.write(before: ("work", nine, nine.addingTimeInterval(3600)), after: nil,
                                             throughFuture: true)
        XCTAssertEqual(scope.ranges, [DateInterval(start: nine, end: .distantFuture)])
    }
}

extension IndexedCalendarEventSourceTests {
    func testScopedWriteRefetchesJustItsMonthAndAnnouncesIt() async throws {
        await service.coordinator.runUntilIdle()
        _ = source.markersByDaySync(in: thisMonth(), calendar: calendar)
        fake.resetLog()
        let soon = Date().addingTimeInterval(3600)
        fake.events = [fake.event("new", start: soon, title: "Just added")]

        let changed = expectation(forNotification: .calendarEventsDidChange, object: nil)
        EventKitEventEditor.announceWrite(.write(before: nil, after: ("work", soon, soon.addingTimeInterval(3600)),
                                                 throughFuture: false))
        try await Task.sleep(for: .milliseconds(50))
        await service.coordinator.runUntilIdle()
        await fulfillment(of: [changed], timeout: 2)
        XCTAssertEqual(fake.fetchedMonths.first, MonthGrid.month(containing: soon), "the written month goes first")
        XCTAssertEqual(source.markersByDaySync(in: thisMonth(), calendar: calendar).values.flatMap { $0 }.count, 1)
    }
}
