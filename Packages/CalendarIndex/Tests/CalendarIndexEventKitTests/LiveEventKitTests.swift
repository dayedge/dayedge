import CalendarIndex
import EventKit
@testable import CalendarIndexEventKit
import XCTest

/// Indexes the real calendars of this Mac. Opt-in: DAYEDGE_LIVE_EVENTKIT=1
/// (needs Calendar access for the process running the tests).
final class LiveEventKitTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DAYEDGE_LIVE_EVENTKIT"] == "1",
                          "set DAYEDGE_LIVE_EVENTKIT=1 to index real calendars")
    }

    func testIndexesRealCalendars() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CalendarIndexLive-\(UUID().uuidString)/index.sqlite")
        var options = IndexStore.Options()
        options.eraseOnSchemaChange = false
        let store = try IndexStore.open(at: url, options: options)
        let source = EventKitSnapshotSource(qos: .userInitiated)
        let authorization = await source.authorization()
        try XCTSkipUnless(authorization.isAuthorized, "no Calendar access for this process")

        let coordinator = SyncCoordinator(store: store, source: source, conditions: { SyncConditions() })
        let started = Date()
        await coordinator.runUntilIdle()
        let elapsed = Date().timeIntervalSince(started)

        let calendars = try store.activeCalendars()
        let coverage = try store.coverage()
        let range = DateInterval(start: Date().addingTimeInterval(-4 * 365 * 86400), end: Date().addingTimeInterval(4 * 365 * 86400))
        let occurrences = try store.occurrences(in: range)
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        print("""
            [live] \(calendars.count) calendars, \(coverage.count) (calendar, month) chunks, \
            \(occurrences.count) occurrences in \(String(format: "%.2f", elapsed)) s, db \(size / 1024) KB, \
            RSS \(residentMegabytes()) MB
            """)
        XCTAssertFalse(calendars.isEmpty)

        // A second pass over unchanged data writes nothing.
        let before = occurrences.map(\.id)
        await coordinator.noteLifecycle(.activate)
        await coordinator.runUntilIdle()
        XCTAssertEqual(try store.occurrences(in: range).map(\.id), before)

        // Spot-check: the soonest upcoming occurrence is searchable by its title.
        if let next = occurrences.first(where: { $0.snapshot.start > Date() && !$0.snapshot.title.isEmpty }) {
            let hits = try store.search(SearchRequest(text: next.snapshot.title, limit: 500))
            XCTAssertTrue(hits.contains { $0.occurrence.id == next.id }, next.snapshot.title)
        }
    }

    /// Read-only: compare both fetch APIs on one store (including ordered alarms),
    /// then verify the production source against that independent store.
    func testEnumerationMatchesLegacySnapshots() async throws {
        let source = EventKitSnapshotSource(qos: .userInitiated)
        let authorization = await source.authorization()
        try XCTSkipUnless(authorization.isAuthorized, "no Calendar access for this process")
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let range = DateInterval(start: calendar.date(byAdding: .day, value: -31, to: today)!,
                                 end: calendar.date(byAdding: .day, value: 31, to: today)!)
        let inventory = try await source.calendars()
        try XCTSkipIf(inventory.isEmpty, "no calendars to compare")
        let identifiers = inventory.map(\.identifier)
        let actual = try await source.occurrences(in: range, calendars: identifiers)
        let control = try await Self.sameStoreSnapshots(in: range, identifiers: identifiers)
        XCTAssertEqual(try Self.canonical(control.legacy.snapshots), try Self.canonical(control.enumerated),
                       "same-store API comparison must preserve every field, ordered alarm and duplicate occurrence")
        XCTAssertEqual(actual.calendars, control.legacy.calendars)
        // Independent legacy stores also reorder alarms on this Mac. Compare their
        // full values and multiplicities here; the same-store check above is ordered.
        XCTAssertEqual(try Self.canonical(actual.snapshots, unorderedAlarms: true),
                       try Self.canonical(control.legacy.snapshots, unorderedAlarms: true))
    }

    private static func sameStoreSnapshots(in range: DateInterval, identifiers: [String]) async throws
        -> (legacy: SourceFetch, enumerated: [OccurrenceSnapshot]) {
        try await Task.detached {
            try autoreleasepool {
                let store = EKEventStore()
                let calendars = identifiers.compactMap { store.calendar(withIdentifier: $0) }
                guard !calendars.isEmpty else { throw SourceError.calendarsUnavailable }
                let predicate = store.predicateForEvents(withStart: range.start, end: range.end, calendars: calendars)
                let series = SeriesRuleLookup(eventStore: store)
                let legacy = store.events(matching: predicate).compactMap { EventSnapshotMapper.snapshot(of: $0, series: series) }
                var enumerated: [OccurrenceSnapshot] = []
                store.enumerateEvents(matching: predicate) { event, _ in
                    autoreleasepool {
                        if let snapshot = EventSnapshotMapper.snapshot(of: event, series: series) { enumerated.append(snapshot) }
                    }
                }
                return (SourceFetch(snapshots: legacy, calendars: Set(calendars.map(\.calendarIdentifier))), enumerated)
            }
        }.value
    }

    /// Sorting occurrences retains duplicates. The optional alarm sort is ONLY
    /// for independent stores: it retains every alarm field and its multiplicity.
    private static func canonical(_ snapshots: [OccurrenceSnapshot], unorderedAlarms: Bool = false) throws -> [Data] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try snapshots.map { snapshot in
            var value = snapshot
            if unorderedAlarms {
                value.alarms = try value.alarms.map { ($0, try encoder.encode($0)) }
                    .sorted { $0.1.lexicographicallyPrecedes($1.1) }.map(\.0)
            }
            return try encoder.encode(value)
        }.sorted { $0.lexicographicallyPrecedes($1) }
    }

    private func residentMegabytes() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.resident_size) / 1_048_576 : -1
    }
}
