import XCTest
@testable import CalendarIndex

/// Ordinary changes keep an occurrence's row (and id); only unusual events
/// start a new one.
final class IdentityTests: XCTestCase {
    private var store: IndexStore!
    private let october = month("2026-10-01T00:00:00Z")
    private let december = month("2026-12-01T00:00:00Z")
    private var clock = date("2026-10-15T12:00:00Z")

    override func setUpWithError() throws {
        store = try makeStore()
        try store.syncCalendars([CalendarSnapshot(identifier: "A", title: "A")], now: clock)
    }

    @discardableResult
    private func reconcile(_ month: Date, _ snapshots: [OccurrenceSnapshot]) throws -> ReconcileResult {
        clock = clock.addingTimeInterval(60)
        return try store.reconcile(calendarIdentifier: "A", month: month, snapshots: snapshots, fetchedAt: clock)
    }

    private func liveIDs() throws -> [Int64] {
        try store.allRows().filter { !$0.missing }.map(\.id)
    }

    func testEditKeepsRow() throws {
        try reconcile(october, [event("a", start: "2026-10-05T09:00:00Z", title: "One", external: "UID-1")])
        let id = try liveIDs()
        var edited = event("a", start: "2026-10-05T11:00:00Z", hours: 2, title: "Two", external: "UID-1")
        edited.notes = "now with notes"
        XCTAssertEqual(try reconcile(october, [edited]).updated, 1)
        XCTAssertEqual(try liveIDs(), id)
    }

    func testMoveAcrossMonthsKeepsRowWhicheverMonthRefreshesFirst() throws {
        try reconcile(october, [event("a", start: "2026-10-05T09:00:00Z", external: "UID-1")])
        let id = try liveIDs()

        // Old month first: soft-deleted (hidden), then revived by the new one.
        try reconcile(october, [])
        XCTAssertEqual(try liveIDs(), [])
        XCTAssertEqual(try store.occurrences(in: MonthGrid.interval(of: october)).count, 0)
        XCTAssertEqual(try reconcile(december, [event("a", start: "2026-12-05T09:00:00Z", external: "UID-1")]).revived, 1)
        XCTAssertEqual(try liveIDs(), id)

        // New month first: moved in place; the old month doesn't touch it.
        try reconcile(october, [event("a", start: "2026-10-20T09:00:00Z", external: "UID-1")])
        try reconcile(december, [])
        XCTAssertEqual(try liveIDs(), id)
        XCTAssertEqual(try store.occurrences(in: MonthGrid.interval(of: october)).map(\.id), id)
    }

    func testMovedOccurrenceOfSeriesKeepsRow() throws {
        let occurrences = (1...4).map { week in
            event("s", start: String(format: "2026-10-%02dT09:00:00Z", week * 7), title: "Weekly", external: "SERIES", recurring: true)
        }
        try reconcile(october, occurrences)
        let ids = try liveIDs()
        XCTAssertEqual(ids.count, 4)

        // The third occurrence moved to the afternoon of another day (detached).
        var moved = occurrences
        moved[2] = event("s-detached", start: "2026-10-22T15:00:00Z", title: "Weekly (moved)", external: "SERIES/RID=123",
                         recurring: true, occurrence: "2026-10-21T09:00:00Z")
        moved[2].isDetached = true
        let result = try reconcile(october, moved)
        XCTAssertEqual(result.updated, 1)
        XCTAssertEqual(result.inserted, 0)
        XCTAssertEqual(try liveIDs(), ids)
    }

    func testIdentifierChurnWithSameExternalIDKeepsRowAndUpdatesReferences() throws {
        try reconcile(october, [event("old-item", start: "2026-10-05T09:00:00Z", external: "UID-1")])
        let id = try liveIDs()
        try reconcile(october, [event("new-item", start: "2026-10-05T09:00:00Z", external: "UID-1")])
        XCTAssertEqual(try liveIDs(), id)
        XCTAssertEqual(try store.occurrences(in: MonthGrid.interval(of: october)).first?.snapshot.calendarItemIdentifier, "new-item")
    }

    func testDuplicateExternalIDsGetDeterministicKeys() throws {
        let twins = [event("x2", start: "2026-10-05T09:00:00Z", title: "Twin 2", external: "DUP"),
                     event("x1", start: "2026-10-06T09:00:00Z", title: "Twin 1", external: "DUP")]
        XCTAssertEqual(try reconcile(october, twins).inserted, 2)
        let first = try store.allRows()
        XCTAssertEqual(try reconcile(october, twins.reversed()).changedCount, 0)
        XCTAssertEqual(try store.allRows().map(\.id), first.map(\.id))
        XCTAssertEqual(Set(first.map(\.key)), ["x:DUP", "x:DUP#x2"])
    }

    func testDuplicateExternalIDsInDifferentMonthsBothStay() throws {
        try reconcile(october, [event("x1", start: "2026-10-05T09:00:00Z", title: "Oct copy", external: "DUP")])
        try reconcile(december, [event("x2", start: "2026-12-05T09:00:00Z", title: "Dec copy", external: "DUP")])
        let ids = try liveIDs()
        XCTAssertEqual(ids.count, 2)
        for _ in 0..<2 {
            try reconcile(october, [event("x1", start: "2026-10-05T09:00:00Z", title: "Oct copy", external: "DUP")])
            try reconcile(december, [event("x2", start: "2026-12-05T09:00:00Z", title: "Dec copy", external: "DUP")])
        }
        XCTAssertEqual(try liveIDs(), ids)
    }

    func testTombstonePurgedAfterCoverageRefetchOrTTL() throws {
        try reconcile(october, [event("a", start: "2026-10-05T09:00:00Z", external: "UID-1")])
        try reconcile(december, [])
        try reconcile(october, [])  // gone missing
        XCTAssertEqual(try store.purgeTombstones(now: clock, ttl: .seconds(3600)), 0, "December not refetched since")
        try reconcile(december, [])
        XCTAssertEqual(try store.purgeTombstones(now: clock, ttl: .seconds(3600)), 1)

        try reconcile(october, [event("b", start: "2026-10-06T09:00:00Z", external: "UID-2")])
        try reconcile(october, [])
        XCTAssertEqual(try store.purgeTombstones(now: clock.addingTimeInterval(7200), ttl: .seconds(3600)), 1)
        XCTAssertEqual(try store.allRows().count, 0)
    }

    func testAllDayOccurrenceKeyIgnoresTimeZone() {
        var warsaw = Calendar(identifier: .gregorian)
        warsaw.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        // EventKit hands all-day dates out at local midnight.
        let inWarsaw = event("h", start: "2026-10-04T22:00:00Z", hours: 24, external: "BDAY", recurring: true, allDay: true)
        let inNewYork = event("h", start: "2026-10-05T04:00:00Z", hours: 24, external: "BDAY", recurring: true, allDay: true)
        XCTAssertEqual(OccurrenceKey.make(for: inWarsaw, calendar: warsaw), OccurrenceKey.make(for: inNewYork, calendar: newYork))
        XCTAssertEqual(OccurrenceKey.make(for: inWarsaw, calendar: warsaw), "x:BDAY@d2026-10-05")
    }

    func testKeyFallsBackToItemIdentifierAndStripsRID() {
        XCTAssertEqual(OccurrenceKey.make(for: event("local-1", start: "2026-10-05T09:00:00Z")), "i:local-1")
        let detached = event("d", start: "2026-10-05T09:00:00Z", external: "S/RID=99", recurring: true, occurrence: "2026-10-04T09:00:00Z")
        XCTAssertEqual(OccurrenceKey.make(for: detached), "x:S@t\(Int(date("2026-10-04T09:00:00Z").timeIntervalSince1970))")
    }

    func testCalendarReAddedWithNewIdentifierIsNewPartition() throws {
        try reconcile(october, [event("a", start: "2026-10-05T09:00:00Z", external: "UID-1")])
        let change = try store.syncCalendars([CalendarSnapshot(identifier: "A2", title: "A")], now: clock)
        XCTAssertEqual(change.added, ["A2"])
        XCTAssertEqual(change.deactivated, ["A"])
        _ = try store.reconcile(calendarIdentifier: "A2", month: october,
                                snapshots: [event("a", calendar: "A2", start: "2026-10-05T09:00:00Z", external: "UID-1")],
                                fetchedAt: clock)
        let visible = try store.occurrences(in: MonthGrid.interval(of: october))
        XCTAssertEqual(visible.map(\.calendar.identifier), ["A2"], "no duplicate from the old partition")
    }
}

final class SnapshotFormatTests: XCTestCase {
    func testRawOccurrenceDateOnSingleEventDoesNotChangeItsKey() {
        var single = event("a", start: "2026-10-05T09:00:00Z", external: "UID")
        let before = OccurrenceKey.make(for: single)
        single.occurrenceDate = single.start  // EventKit's raw value for a single event
        XCTAssertEqual(OccurrenceKey.make(for: single), before)
        XCTAssertEqual(before, "x:UID")
    }

    func testVersionOnePayloadDecodesWithDefaults() throws {
        let v1 = #"{"calendarIdentifier":"A","calendarItemIdentifier":"i","start":800000000,"end":800003600,"#
            + #""alarms":[{"relativeOffset":-600}],"isRecurring":true}"#
        let snapshot = try SnapshotCoding.decode(OccurrenceSnapshot.self, from: Data(v1.utf8))
        XCTAssertFalse(snapshot.hasOwnRecurrenceRules)
        XCTAssertEqual(snapshot.alarms, [AlarmSnapshot(relativeOffset: -600)])
        XCTAssertFalse(snapshot.alarms[0].isLocationBased)
    }
}
