import GRDB
import XCTest
@testable import CalendarIndex

final class IndexStoreTests: XCTestCase {
    private var store: IndexStore!
    private let october = month("2026-10-01T00:00:00Z")
    private let november = month("2026-11-01T00:00:00Z")
    private let fetchedAt = date("2026-10-15T12:00:00Z")

    override func setUpWithError() throws {
        store = try makeStore()
        try store.syncCalendars([CalendarSnapshot(identifier: "A", title: "Work")], now: fetchedAt)
    }

    private func reconcile(_ month: Date, _ snapshots: [OccurrenceSnapshot], calendar: String = "A") throws -> ReconcileResult {
        try store.reconcile(calendarIdentifier: calendar, month: month, snapshots: snapshots, fetchedAt: fetchedAt)
    }

    private func titles(in interval: DateInterval) throws -> [String] {
        try store.occurrences(in: interval).map(\.snapshot.title)
    }

    func testInsertUpdateDelete() throws {
        let a = event("a", start: "2026-10-05T09:00:00Z", title: "Standup")
        let b = event("b", start: "2026-10-06T09:00:00Z", title: "Review")
        XCTAssertEqual(try reconcile(october, [a, b]).inserted, 2)
        XCTAssertEqual(try titles(in: MonthGrid.interval(of: october)), ["Standup", "Review"])

        var edited = a
        edited.title = "Daily standup"
        let result = try reconcile(october, [edited])
        XCTAssertEqual(result.updated, 1)
        XCTAssertEqual(result.softDeleted, 1)
        XCTAssertEqual(try titles(in: MonthGrid.interval(of: october)), ["Daily standup"])
    }

    func testUnchangedRefetchWritesNoOccurrenceRows() throws {
        let events = [event("a", start: "2026-10-05T09:00:00Z", notes: "agenda"),
                      event("b", start: "2026-10-06T09:00:00Z")]
        _ = try reconcile(october, events)
        let before = try store.totalChanges()
        let result = try reconcile(october, events)
        XCTAssertEqual(result.changedCount, 0)
        XCTAssertEqual(result.unchanged, 2)
        XCTAssertNil(result.changedSpan)
        // Only the coverage timestamp is written.
        XCTAssertEqual(try store.totalChanges() - before, 1)
    }

    func testEventAcrossMonthBoundaryIsOneRowOwnedByItsStartMonth() throws {
        let overnight = event("n", start: "2026-10-31T22:00:00Z", hours: 4, title: "Overnight")
        // EventKit returns it for both months (overlap).
        _ = try reconcile(october, [overnight])
        _ = try reconcile(november, [overnight])
        XCTAssertEqual(try store.allRows().count, 1)
        XCTAssertEqual(try titles(in: MonthGrid.interval(of: november)), ["Overnight"])
        XCTAssertEqual(try titles(in: DateInterval(start: date("2026-11-01T00:00:00Z"), duration: 3600)), ["Overnight"])

        // November never deletes what October owns.
        _ = try reconcile(november, [])
        XCTAssertEqual(try titles(in: MonthGrid.interval(of: november)), ["Overnight"])
        _ = try reconcile(october, [overnight])
        XCTAssertEqual(try store.allRows().map(\.missing), [false])
    }

    func testOverlapReadFindsLongEventsStartedBeforeTheRange() throws {
        let trip = event("t", start: "2026-10-01T00:00:00Z", hours: 24 * 20, title: "Trip", allDay: true)
        _ = try reconcile(october, [trip])
        XCTAssertEqual(try titles(in: DateInterval(start: date("2026-10-18T00:00:00Z"), duration: 86400)), ["Trip"])
        XCTAssertEqual(try titles(in: DateInterval(start: date("2026-10-25T00:00:00Z"), duration: 86400)), [])
    }

    func testZeroLengthEventAtRangeStartIsIncluded() throws {
        let marker = event("z", start: "2026-10-10T00:00:00Z", hours: 0, title: "Marker")
        _ = try reconcile(october, [marker])
        XCTAssertEqual(try titles(in: DateInterval(start: date("2026-10-10T00:00:00Z"), duration: 86400)), ["Marker"])
    }

    func testDayMarkersSkipPayloads() throws {
        _ = try reconcile(october, [event("a", start: "2026-10-05T09:00:00Z", participation: .declined)])
        let markers = try store.dayMarkers(in: MonthGrid.interval(of: october))
        XCTAssertEqual(markers.map(\.calendarIdentifier), ["A"])
        XCTAssertEqual(markers.first?.participation, .declined)
    }

    func testInactiveCalendarIsHiddenAtOnceAndPurgedLater() throws {
        _ = try reconcile(october, [event("a", start: "2026-10-05T09:00:00Z", title: "Gone soon")])
        let change = try store.syncCalendars([], now: fetchedAt)
        XCTAssertEqual(change.deactivated, ["A"])
        XCTAssertEqual(try titles(in: MonthGrid.interval(of: october)), [])
        XCTAssertEqual(try store.search(SearchRequest(text: "gone")).count, 0)
        XCTAssertEqual(try store.allRows().count, 1)

        XCTAssertGreaterThan(try store.purgeInactive(), 0)
        XCTAssertEqual(try store.allRows().count, 0)
    }

    func testCoverageInfoReportsMissingMonths() throws {
        _ = try reconcile(october, [])
        let info = try store.coverageInfo(for: DateInterval(start: october, end: MonthGrid.month(october, adding: 2)))
        XCTAssertEqual(info.missingMonths, [november])
        XCTAssertEqual(info.oldestFetch, fetchedAt)
    }

    func testNewIndexWithoutCalendarsReportsMonthsMissing() throws {
        let fresh = try makeStore()
        XCTAssertEqual(try fresh.coverageInfo(for: MonthGrid.interval(of: october)).missingMonths, [october])
    }

    func testReconcileRejectsUnknownCalendar() {
        XCTAssertThrowsError(try reconcile(october, [], calendar: "nope"))
    }

    func testCalendarPayloadUpdatesWithoutNewPartition() throws {
        _ = try reconcile(october, [event("a", start: "2026-10-05T09:00:00Z")])
        let id = try store.allRows().first?.id
        let change = try store.syncCalendars([CalendarSnapshot(identifier: "A", title: "Renamed")], now: fetchedAt)
        XCTAssertEqual(change.updated, ["A"])
        XCTAssertEqual(try store.occurrences(in: MonthGrid.interval(of: october)).first?.calendar.title, "Renamed")
        XCTAssertEqual(try store.allRows().first?.id, id)
    }
}

final class SearchTests: XCTestCase {
    private var store: IndexStore!
    private let october = month("2026-10-01T00:00:00Z")

    override func setUpWithError() throws {
        store = try makeStore()
        try store.syncCalendars([CalendarSnapshot(identifier: "A", title: "Work"), CalendarSnapshot(identifier: "B", title: "Home")],
                                now: Date())
        _ = try store.reconcile(calendarIdentifier: "A", month: october, snapshots: [
            event("1", start: "2026-10-05T09:00:00Z", title: "Spotkanie zespołu"),
            event("2", start: "2026-10-06T09:00:00Z", title: "Dentist", location: "Main Street Clinic"),
            event("3", start: "2026-10-07T09:00:00Z", title: "Sync",
                  attendees: [AttendeeSnapshot(name: "Jane Doe", email: "jane@example.com", status: .accepted, isCurrentUser: false)]),
            event("4", start: "2026-10-08T09:00:00Z", title: "Planning", notes: "Bring the roadmap", participation: .declined),
        ], fetchedAt: Date())
        _ = try store.reconcile(calendarIdentifier: "B", month: october, snapshots: [
            event("5", calendar: "B", start: "2026-10-09T09:00:00Z", title: "Dentist follow-up"),
        ], fetchedAt: Date())
    }

    private func search(_ text: String, _ configure: (inout SearchRequest) -> Void = { _ in }) throws -> [String] {
        var request = SearchRequest(text: text)
        configure(&request)
        return try store.search(request, now: date("2026-10-05T00:00:00Z")).map(\.occurrence.snapshot.title)
    }

    func testPrefixAndDiacriticsInsensitive() throws {
        XCTAssertEqual(try search("spotk"), ["Spotkanie zespołu"])
        XCTAssertEqual(try search("spotkań"), ["Spotkanie zespołu"])  // "spotkan…", diacritics folded
        XCTAssertEqual(try search("spotkanieX"), [])
        XCTAssertEqual(try search("SPOTKANIE"), ["Spotkanie zespołu"])
        XCTAssertEqual(try search("Spótkanie"), ["Spotkanie zespołu"])
    }

    func testSearchesLocationPeopleAndNotes() throws {
        XCTAssertEqual(try search("clinic"), ["Dentist"])
        XCTAssertEqual(try search("jane"), ["Sync"])
        XCTAssertEqual(try search("example.com"), ["Sync"])
        XCTAssertEqual(try search("roadmap"), ["Planning"])
    }

    func testAllWordsRequired() throws {
        XCTAssertEqual(try search("dentist follow"), ["Dentist follow-up"])
    }

    func testTitleMatchesRankAboveNotes() throws {
        _ = try store.reconcile(calendarIdentifier: "A", month: october, snapshots: [
            event("1", start: "2026-10-05T09:00:00Z", title: "Spotkanie zespołu"),
            event("2", start: "2026-10-06T09:00:00Z", title: "Dentist", location: "Main Street Clinic"),
            event("3", start: "2026-10-07T09:00:00Z", title: "Sync",
                  attendees: [AttendeeSnapshot(name: "Jane Doe", email: "jane@example.com", status: .accepted, isCurrentUser: false)]),
            event("4", start: "2026-10-08T09:00:00Z", title: "Planning", notes: "Bring the roadmap", participation: .declined),
            event("6", start: "2026-10-20T09:00:00Z", title: "Roadmap review"),
        ], fetchedAt: Date())
        XCTAssertEqual(try search("roadmap"), ["Roadmap review", "Planning"])
    }

    func testFilters() throws {
        XCTAssertEqual(try search("dentist") { $0.includedCalendars = ["B"] }, ["Dentist follow-up"])
        XCTAssertEqual(try search("dentist") { $0.excludedCalendars = ["B"] }, ["Dentist"])
        XCTAssertEqual(try search("planning") { $0.includesDeclined = false }, [])
        XCTAssertEqual(try search("dentist") {
            $0.interval = DateInterval(start: date("2026-10-09T00:00:00Z"), duration: 86400)
        }, ["Dentist follow-up"])
    }

    func testHostileInputIsJustWords() throws {
        for input in ["\"", "NEAR(a b)", "title:dentist", "dentist OR sync", "*", "^dent", "a\" OR \"b", "'); DROP TABLE occurrence; --"] {
            XCTAssertNoThrow(try search(input), input)
        }
        XCTAssertEqual(try search("title:dentist"), [])  // "title" AND "dentist", not a column filter
        XCTAssertEqual(try search("dentist OR sync"), [])  // three required words
        XCTAssertEqual(try search("   "), [])
        XCTAssertEqual(SearchQuery.ftsExpression(for: "a\"b"), "\"a\"* \"b\"*")
    }

    func testFTS5IsAvailableInSystemSQLite() throws {
        let options = try store.pool.read { try String.fetchAll($0, sql: "PRAGMA compile_options") }
        XCTAssertTrue(options.contains("ENABLE_FTS5"))
    }
}

final class SearchMatchTests: XCTestCase {
    private let october = month("2026-10-01T00:00:00Z")

    func testMatchesInDateOrderWithoutPayloadsAndLoadByID() throws {
        let store = try makeStore()
        try store.syncCalendars([CalendarSnapshot(identifier: "A", title: "A"), CalendarSnapshot(identifier: "B", title: "B")],
                                now: Date())
        _ = try store.reconcile(calendarIdentifier: "A", month: october, snapshots: [
            event("2", start: "2026-10-09T09:00:00Z", title: "Standup two"),
            event("1", start: "2026-10-02T09:00:00Z", title: "Standup one"),
            event("x", start: "2026-10-05T09:00:00Z", title: "Unrelated"),
        ], fetchedAt: Date())
        _ = try store.reconcile(calendarIdentifier: "B", month: october, snapshots: [
            event("3", calendar: "B", start: "2026-10-05T09:00:00Z", title: "Standup hidden"),
        ], fetchedAt: Date())

        let all = try store.searchMatches(SearchRequest(text: "standup"))
        XCTAssertEqual(all.map(\.start), [date("2026-10-02T09:00:00Z"), date("2026-10-05T09:00:00Z"), date("2026-10-09T09:00:00Z")])
        XCTAssertEqual(try store.searchMatches(SearchRequest(text: "standup", excludedCalendars: ["B"])).count, 2)

        let loaded = try store.occurrences(ids: [all[2].id, all[0].id])
        XCTAssertEqual(loaded.map(\.snapshot.title), ["Standup one", "Standup two"], "just those, in date order")
    }

    func testDeclinedRuleKeepsOrganizerCancellations() throws {
        let store = try makeStore()
        try store.syncCalendars([CalendarSnapshot(identifier: "A", title: "A")], now: Date())
        var cancelled = event("c", start: "2026-10-06T09:00:00Z", title: "Review cancelled", participation: .declined)
        cancelled.status = .canceled
        _ = try store.reconcile(calendarIdentifier: "A", month: october, snapshots: [
            event("d", start: "2026-10-05T09:00:00Z", title: "Review declined", participation: .declined),
            cancelled,
            event("k", start: "2026-10-07T09:00:00Z", title: "Review kept"),
        ], fetchedAt: Date())
        let hidden = try store.searchMatches(SearchRequest(text: "review", includesDeclined: false))
        XCTAssertEqual(hidden.count, 2, "declined by me is hidden; an organizer cancellation stays")
        XCTAssertEqual(try store.searchMatches(SearchRequest(text: "review")).count, 3)
    }
}

final class SearchRankedTests: XCTestCase {
    func testTitleMatchesBeatNotesAndAnOldStrongMatchBeatsANearWeakOne() throws {
        let store = try makeStore()
        let october = month("2026-10-01T00:00:00Z")
        let older = month("2024-05-01T00:00:00Z")
        try store.syncCalendars([CalendarSnapshot(identifier: "A", title: "A")], now: Date())
        _ = try store.reconcile(calendarIdentifier: "A", month: october, snapshots: [
            event("weak", start: "2026-10-06T09:00:00Z", title: "Weekly sync", notes: "refinement widok agenda"),
        ], fetchedAt: Date())
        _ = try store.reconcile(calendarIdentifier: "A", month: older, snapshots: [
            event("strong", start: "2024-05-14T09:00:00Z", title: "Refinement Widok 360"),
        ], fetchedAt: Date())
        let ranked = try store.searchRanked(SearchRequest(text: "refinement widok", limit: 10),
                                            now: date("2026-10-05T12:00:00Z"))
        XCTAssertEqual(ranked.map(\.title), ["Refinement Widok 360", "Weekly sync"])
    }

    func testNearestUpcomingMatchesAreCandidatesEvenWhenMoreScoreBetter() throws {
        let store = try makeStore()
        try store.syncCalendars([CalendarSnapshot(identifier: "A", title: "A")], now: Date())
        // Old meetings with a short text score better than upcoming ones
        // with long notes; with a limit of 2 the upcoming ones still come.
        _ = try store.reconcile(calendarIdentifier: "A", month: month("2024-03-01T00:00:00Z"), snapshots: [
            event("o1", start: "2024-03-27T09:00:00Z", title: "Standup", notes: "szmurlo"),
            event("o2", start: "2024-03-28T09:00:00Z", title: "Standup", notes: "szmurlo"),
            event("o3", start: "2024-03-29T09:00:00Z", title: "Standup", notes: "szmurlo"),
        ], fetchedAt: Date())
        let long = "szmurlo " + String(repeating: "agenda item ", count: 40)
        _ = try store.reconcile(calendarIdentifier: "A", month: month("2026-10-01T00:00:00Z"), snapshots: [
            event("past", start: "2026-10-01T09:00:00Z", title: "Daily", notes: long),
            event("next", start: "2026-10-05T09:00:00Z", title: "Daily", notes: long),
            event("later", start: "2026-10-06T09:00:00Z", title: "Daily", notes: long),
        ], fetchedAt: Date())
        let ranked = try store.searchRanked(SearchRequest(text: "szmurlo", limit: 2), now: date("2026-10-03T12:00:00Z"),
                                            upcomingFrom: date("2026-10-03T00:00:00Z"))
        let starts = ranked.map { $0.match.start }
        XCTAssertTrue(starts.contains(date("2026-10-05T09:00:00Z")), "the next one")
        XCTAssertTrue(starts.contains(date("2026-10-06T09:00:00Z")))
        XCTAssertEqual(Set(ranked.map(\.match.id)).count, ranked.count, "no duplicates")
    }

    func testTitleOnlyCandidatesFindNearTitleMatchesAmongManyOthers() throws {
        let store = try makeStore()
        try store.syncCalendars([CalendarSnapshot(identifier: "A", title: "A")], now: Date())
        _ = try store.reconcile(calendarIdentifier: "A", month: month("2026-10-01T00:00:00Z"), snapshots: [
            event("n1", start: "2026-10-04T09:00:00Z", title: "Sync", notes: "budget"),
            event("n2", start: "2026-10-04T10:00:00Z", title: "Sync", notes: "budget"),
            event("t", start: "2026-10-20T09:00:00Z", title: "Budget review"),
        ], fetchedAt: Date())
        let ranked = try store.searchRanked(SearchRequest(text: "budget", limit: 1), now: date("2026-10-03T12:00:00Z"),
                                            upcomingFrom: date("2026-10-03T00:00:00Z"))
        XCTAssertTrue(ranked.map(\.title).contains("Budget review"))
    }
}

final class SearchOperatorTests: XCTestCase {
    private var store: IndexStore!

    private func person(_ name: String, _ email: String) -> AttendeeSnapshot {
        AttendeeSnapshot(name: name, email: email, status: .accepted, isCurrentUser: false)
    }

    override func setUpWithError() throws {
        store = try makeStore()
        try store.syncCalendars([CalendarSnapshot(identifier: "A", title: "A")], now: Date())
        var organizedByAnna = event("a", start: "2026-10-05T09:00:00Z", title: "Refinement widok",
                                    attendees: [person("Anna Nowak", "anna@x.pl"), person("Paweł Kowalski", "pawel@x.pl")])
        organizedByAnna.organizer = OrganizerSnapshot(name: "Anna Nowak", email: "anna@x.pl", isCurrentUser: false)
        var organizedByPawel = event("p", start: "2026-10-06T09:00:00Z", title: "Daily",
                                     notes: "refinement notes", attendees: [person("Anna Nowak", "anna@x.pl")])
        organizedByPawel.organizer = OrganizerSnapshot(name: "Paweł Kowalski", email: "pawel@x.pl", isCurrentUser: false)
        _ = try store.reconcile(calendarIdentifier: "A", month: month("2026-10-01T00:00:00Z"),
                                snapshots: [organizedByAnna, organizedByPawel], fetchedAt: Date())
    }

    private func titles(_ request: SearchRequest) throws -> [String] {
        let ids = try store.searchMatches(request).map(\.id)
        return try store.occurrences(ids: ids).map(\.snapshot.title)
    }

    func testFromMatchesTheOrganizerOnlyAndWithMatchesPeople() throws {
        XCTAssertEqual(try titles(SearchRequest(text: "", organizer: "anna")), ["Refinement widok"])
        XCTAssertEqual(try titles(SearchRequest(text: "", attendee: "anna")), ["Refinement widok", "Daily"])
        XCTAssertEqual(try titles(SearchRequest(text: "", organizer: "Kowalski")), ["Daily"])
    }

    func testFromMeIsMyOrganizedOrMyOwnEventsOnly() throws {
        var mine = event("m", start: "2026-10-07T09:00:00Z", title: "My meeting", attendees: [person("Anna Nowak", "anna@x.pl")])
        mine.organizer = OrganizerSnapshot(name: "Me", email: "me@x.pl", isCurrentUser: true)
        let own = event("o", start: "2026-10-08T09:00:00Z", title: "Dentist")
        _ = try store.reconcile(calendarIdentifier: "A", month: month("2026-10-01T00:00:00Z"),
                                snapshots: [mine, own] + (try store.occurrences(in: MonthGrid.interval(of: month("2026-10-01T00:00:00Z")))
                                    .map(\.snapshot)), fetchedAt: Date())
        try store.syncCalendars([CalendarSnapshot(identifier: "A", title: "A"),
                                 CalendarSnapshot(identifier: "H", title: "Holidays", allowsModifications: false)], now: Date())
        _ = try store.reconcile(calendarIdentifier: "H", month: month("2026-10-01T00:00:00Z"),
                                snapshots: [event("h", calendar: "H", start: "2026-10-09T00:00:00Z", title: "Holiday", allDay: true)],
                                fetchedAt: Date())
        XCTAssertEqual(try titles(SearchRequest(text: "", organizedByMe: true)), ["My meeting", "Dentist"])
        XCTAssertEqual(try titles(SearchRequest(text: "dentist", organizedByMe: true)), ["Dentist"])
    }

    func testSubjectIsTitleOnlyAndCombinesWithFreeText() throws {
        XCTAssertEqual(try titles(SearchRequest(text: "refinement")), ["Refinement widok", "Daily"])
        XCTAssertEqual(try titles(SearchRequest(text: "", titleText: "refinement")), ["Refinement widok"])
        XCTAssertEqual(try titles(SearchRequest(text: "notes", titleText: "daily")), ["Daily"])
        XCTAssertEqual(try titles(SearchRequest(text: "notes", titleText: "refinement")), [])
    }

    func testADateRangeAloneSearchesWithoutText() throws {
        let day = DateInterval(start: date("2026-10-06T00:00:00Z"), duration: 86400)
        XCTAssertEqual(try titles(SearchRequest(text: "", interval: day)), ["Daily"])
        XCTAssertEqual(try store.searchRanked(SearchRequest(text: "", interval: day)).map(\.title), ["Daily"])
        XCTAssertEqual(try titles(SearchRequest(text: "")), [], "nothing to match, no range: nothing")
    }

    func testPeopleByRoleAndPrefixMostFrequentFirst() throws {
        XCTAssertEqual(try store.people(.organizer, prefix: "").map(\.displayName).sorted(), ["Anna Nowak", "Paweł Kowalski"])
        let attendees = try store.people(.attendee, prefix: "")
        XCTAssertEqual(attendees.first?.displayName, "Anna Nowak", "on both events")
        XCTAssertEqual(attendees.first?.email, "anna@x.pl")
        XCTAssertEqual(try store.people(.attendee, prefix: "kow").map(\.displayName), ["Paweł Kowalski"])
        XCTAssertEqual(try store.people(.organizer, prefix: "now").map(\.displayName), ["Anna Nowak"])
    }
}
