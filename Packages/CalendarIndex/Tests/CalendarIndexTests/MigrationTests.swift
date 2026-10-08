import GRDB
import XCTest
@testable import CalendarIndex

final class MigrationTests: XCTestCase {
    private let october = month("2026-10-01T00:00:00Z")

    private func seed(_ url: URL, options: IndexStore.Options = testOptions()) throws -> Int64 {
        let store = try IndexStore.open(at: url, options: options)
        try store.syncCalendars([CalendarSnapshot(identifier: "A", title: "A")], now: Date())
        _ = try store.reconcile(calendarIdentifier: "A", month: october,
                                snapshots: [event("a", start: "2026-10-05T09:00:00Z", title: "Kept", external: "UID")],
                                fetchedAt: Date())
        let id = try store.allRows()[0].id
        try store.close()
        return id
    }

    private func url() -> URL { temporaryDirectory().appendingPathComponent("index.sqlite") }

    func testStructuralMigrationKeepsRowsAndIDs() throws {
        let url = url()
        let id = try seed(url)
        var options = testOptions()
        options.extraMigrations = [("v2-test-column", { db in
            try db.execute(sql: "ALTER TABLE occurrence ADD COLUMN color_hint TEXT")
        })]
        let store = try IndexStore.open(at: url, options: options)
        XCTAssertEqual(try store.allRows().map(\.id), [id])
        XCTAssertEqual(try store.search(SearchRequest(text: "kept")).map(\.occurrence.id), [id])
    }

    func testCoverageResetLeavesRowsReadableAndMonthsDue() throws {
        let url = url()
        _ = try seed(url)
        var options = testOptions()
        options.extraMigrations = [("v2-refetch", { try IndexMigrations.resetCoverage($0) })]
        let store = try IndexStore.open(at: url, options: options)
        XCTAssertEqual(try store.occurrences(in: MonthGrid.interval(of: october)).map(\.snapshot.title), ["Kept"])
        XCTAssertEqual(try store.coverage().values.map(\.timeIntervalSince1970), [0])
    }

    func testSearchRecreationKeepsRowIDs() throws {
        let url = url()
        let id = try seed(url)
        var options = testOptions()
        options.extraMigrations = [("v2-tokenizer", {
            try IndexMigrations.recreateSearch($0, columns: IndexMigrations.searchColumns, tokenize: "unicode61 remove_diacritics 2", prefix: "2 3 4")
        })]
        let store = try IndexStore.open(at: url, options: options)
        XCTAssertEqual(try store.search(SearchRequest(text: "kep")).map(\.occurrence.id), [id])
    }

    func testOrganizerBackfillComesFromStoredPayloads() throws {
        let url = url()
        let store = try IndexStore.open(at: url, options: testOptions())
        try store.syncCalendars([CalendarSnapshot(identifier: "A", title: "A")], now: Date())
        var organized = event("a", start: "2026-10-05T09:00:00Z", title: "Planning")
        organized.organizer = OrganizerSnapshot(name: "Anna Nowak", email: "anna@x.pl", isCurrentUser: false)
        _ = try store.reconcile(calendarIdentifier: "A", month: october, snapshots: [organized], fetchedAt: Date())
        // As a v2 database would be: the column there, but empty.
        try store.pool.write { try $0.execute(sql: "UPDATE occurrence SET organizer_text = NULL") }
        XCTAssertTrue(try store.searchMatches(SearchRequest(text: "", organizer: "anna")).isEmpty)
        try store.pool.write { try IndexMigrations.backfillOrganizers($0) }
        XCTAssertEqual(try store.searchMatches(SearchRequest(text: "", organizer: "anna")).count, 1)
    }

    func testOldPayloadDecodesAfterFieldsAreAdded() throws {
        let minimal = #"{"calendarIdentifier":"A","calendarItemIdentifier":"i","start":800000000,"end":800003600}"#
        let snapshot = try SnapshotCoding.decode(OccurrenceSnapshot.self, from: Data(minimal.utf8))
        XCTAssertEqual(snapshot.title, "")
        XCTAssertEqual(snapshot.attendees, [])
        XCTAssertEqual(snapshot.availability, .busy)
    }

    func testDatabaseFromNewerBuildIsReplaced() throws {
        let url = url()
        var newer = testOptions()
        newer.extraMigrations = [("v99-future", { _ in })]
        _ = try seed(url, options: newer)
        let store = try IndexStore.open(at: url, options: testOptions())
        XCTAssertEqual(try store.allRows().count, 0)
        XCTAssertEqual(try store.coverage().count, 0)
    }

    func testGarbageFileIsReplaced() throws {
        let url = url()
        try Data(repeating: 0x42, count: 8192).write(to: url)
        let store = try IndexStore.open(at: url, options: testOptions())
        try store.syncCalendars([CalendarSnapshot(identifier: "A", title: "A")], now: Date())
        XCTAssertEqual(try store.activeCalendars().map(\.identifier), ["A"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path + ".new"))
    }

    func testTransientLockIsRetriedAndDataKept() throws {
        let url = url()
        let id = try seed(url)
        let blocker = try DatabaseQueue(path: url.path)
        let locked = expectation(description: "locked")
        let release = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            try? blocker.inDatabase { db in
                try db.execute(sql: "BEGIN EXCLUSIVE")
                locked.fulfill()
                release.wait()
                try db.execute(sql: "COMMIT")
            }
        }
        wait(for: [locked], timeout: 5)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { release.signal() }

        var options = testOptions()
        options.busyTimeout = 0.05
        options.openAttempts = 6
        options.retryBackoff = 0.05
        let store = try IndexStore.open(at: url, options: options)
        XCTAssertEqual(try store.allRows().map(\.id), [id])
    }

    func testFilesArePrivate() throws {
        let url = url()
        _ = try seed(url)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
    }
}

final class PayloadCodingTests: XCTestCase {
    func testCompressedAndPlainPayloadsBothDecode() throws {
        let snapshot = event("a", start: "2026-10-05T09:00:00Z", title: "Weekly", notes: String(repeating: "Join the meeting ", count: 200))
        let stored = try SnapshotCoding.payload(snapshot)
        let plain = try SnapshotCoding.encode(snapshot)
        XCTAssertLessThan(stored.data.count, plain.count / 4)
        XCTAssertEqual(try SnapshotCoding.decode(OccurrenceSnapshot.self, from: stored.data), snapshot)
        XCTAssertEqual(try SnapshotCoding.decode(OccurrenceSnapshot.self, from: plain), snapshot)
        XCTAssertEqual(stored.fingerprint, Fingerprint.of(plain), "fingerprint is of the canonical JSON")
    }
}

final class StatusMigrationTests: XCTestCase {
    func testV2AddsStatusRewritesUnchangedRowsAndKeepsIDs() throws {
        let url = temporaryDirectory().appendingPathComponent("index.sqlite")
        // A database as stage 1 left it: v1 only.
        var v1 = testOptions()
        v1.extraMigrations = []
        let queue = try DatabaseQueue(path: url.path)
        var migrator = DatabaseMigrator()
        for migration in IndexMigrations.all.prefix(1) { migrator.registerMigration(migration.identifier, migrate: migration.migrate) }
        try migrator.migrate(queue)
        try queue.close()

        let cancelled = { () -> OccurrenceSnapshot in
            var s = event("a", start: "2026-10-05T09:00:00Z", title: "Called off", external: "UID")
            s.status = .canceled
            return s
        }()
        let october = month("2026-10-01T00:00:00Z")
        let store = try IndexStore.open(at: url, options: v1)
        try store.syncCalendars([CalendarSnapshot(identifier: "A", title: "A")], now: Date())
        _ = try store.reconcile(calendarIdentifier: "A", month: october, snapshots: [cancelled], fetchedAt: Date())
        let id = try store.allRows()[0].id
        XCTAssertEqual(try store.dayMarkers(in: MonthGrid.interval(of: october)).first?.status, .canceled)

        // Simulate a row written before the column existed, then migrate again is a no-op;
        // instead verify the migration's effects on a fresh v1 database below.
        try store.pool.write { try $0.execute(sql: "UPDATE occurrence SET status = NULL, snapshot_version = 0") }
        let result = try store.reconcile(calendarIdentifier: "A", month: october, snapshots: [cancelled], fetchedAt: Date())
        XCTAssertEqual(result.updated, 1, "an old-version row is rewritten even though its content is unchanged")
        XCTAssertEqual(try store.dayMarkers(in: MonthGrid.interval(of: october)).first?.status, .canceled)
        XCTAssertEqual(try store.allRows().map(\.id), [id])
    }

    func testV2OnAV1DatabaseKeepsRowsAndMarksEverythingDue() throws {
        let url = temporaryDirectory().appendingPathComponent("index.sqlite")
        let queue = try DatabaseQueue(path: url.path)
        var migrator = DatabaseMigrator()
        let v1 = IndexMigrations.all[0]
        migrator.registerMigration(v1.identifier, migrate: v1.migrate)
        try migrator.migrate(queue)
        try queue.write { db in
            try db.execute(sql: "INSERT INTO calendar (ek_identifier, payload) VALUES ('A', ?)",
                           arguments: [try SnapshotCoding.encode(CalendarSnapshot(identifier: "A", title: "A"))])
            let snapshot = event("a", start: "2026-10-05T09:00:00Z", title: "Kept", external: "UID")
            try db.execute(sql: """
                INSERT INTO occurrence (calendar_id, occurrence_key, calendar_item_identifier, start, "end", is_all_day,
                    title, fingerprint, snapshot_version, payload)
                VALUES (1, 'x:UID', 'a', ?, ?, 0, 'Kept', 1, 2, ?)
                """, arguments: [snapshot.start.timeIntervalSince1970, snapshot.end.timeIntervalSince1970,
                                 try SnapshotCoding.encode(snapshot)])
            try db.execute(sql: "INSERT INTO coverage VALUES (1, ?, ?)",
                           arguments: [month("2026-10-01T00:00:00Z").timeIntervalSince1970, Date().timeIntervalSince1970])
        }
        try queue.close()

        let store = try IndexStore.open(at: url, options: testOptions())
        XCTAssertEqual(try store.allRows().map(\.title), ["Kept"])
        XCTAssertNil(try store.dayMarkers(in: MonthGrid.interval(of: month("2026-10-01T00:00:00Z"))).first?.status)
        XCTAssertEqual(try store.coverage().values.map(\.timeIntervalSince1970), [0], "every month due again")
        let version = try store.pool.read { try Int.fetchOne($0, sql: "SELECT snapshot_version FROM occurrence") }
        XCTAssertEqual(version, 0)
    }
}
