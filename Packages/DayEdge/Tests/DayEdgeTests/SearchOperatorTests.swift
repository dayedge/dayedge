import CalendarIndex
import XCTest
@testable import Shell
@testable import Domain
@testable import Intelligence

final class SearchQuerySyntaxTests: XCTestCase {
    func testOperatorsComeOutAndWordsStay() {
        let parsed = SearchQuerySyntax.parse("refinement widok from:anna DAY:today")
        XCTAssertEqual(parsed.freeText, "refinement widok")
        XCTAssertEqual(parsed.values, [.from: "anna", .day: "today"], "keys in any case")
        XCTAssertTrue(parsed.hasOperators)
    }

    func testQuotedValuesKeepTheirSpaces() {
        let parsed = SearchQuerySyntax.parse(#"subject:"Widok 360" with:"Jon Nest" plan"#)
        XCTAssertEqual(parsed.values, [.subject: "Widok 360", .with: "Jon Nest"])
        XCTAssertEqual(parsed.freeText, "plan")
    }

    func testUnknownKeysAndPlainColonsAreWords() {
        let parsed = SearchQuerySyntax.parse("owner:anna 10:30 review")
        XCTAssertEqual(parsed.freeText, "owner:anna 10:30 review")
        XCTAssertFalse(parsed.hasOperators)
    }

    func testAnEmptyOperatorAppliesNothingButIsBeingEdited() {
        let parsed = SearchQuerySyntax.parse("refinement from:")
        XCTAssertEqual(parsed.values, [:])
        XCTAssertEqual(parsed.freeText, "refinement")
        XCTAssertEqual(parsed.editing, .init(op: .from, partial: "", tokenStart: 11))
    }

    func testEditingIsOnlyTheLastTokenBeforeASpace() {
        XCTAssertEqual(SearchQuerySyntax.parse("with:an").editing, .init(op: .with, partial: "an", tokenStart: 0))
        XCTAssertEqual(SearchQuerySyntax.parse("refinement fr").editing, .init(op: nil, partial: "fr", tokenStart: 11))
        XCTAssertNil(SearchQuerySyntax.parse("with:anna ").editing)
    }

    func testTIsShortForType() {
        XCTAssertEqual(SearchQuerySyntax.parse("invoice t:t").values, [.type: "t"])
        XCTAssertEqual(SearchQueryResolver.kind("e"), .event)
        XCTAssertEqual(SearchQueryResolver.kind("t"), .task)
    }

    func testRepeatedOperatorLastWins() {
        XCTAssertEqual(SearchQuerySyntax.parse("type:event type:task").values, [.type: "task"])
    }

    func testReplacingTheEditedToken() {
        XCTAssertEqual(SearchQuerySyntax.replacingToken(in: "plan from:jo", from: 5, with: #"from:"Jon Nest" "#),
                       #"plan from:"Jon Nest" "#)
        XCTAssertEqual(SearchQuerySyntax.quoted("Jon Nest"), #""Jon Nest""#)
        XCTAssertEqual(SearchQuerySyntax.quoted("anna"), "anna")
    }
}

final class SearchQueryResolverTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }()
    /// Saturday 3 Oct 2026, noon.
    private var reference: Date { day(2026, 10, 3, hour: 12) }

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func resolve(_ query: String) async -> SearchQueryParts {
        await SearchQueryResolver.resolve(query, referenceDate: reference, calendar: calendar)
    }

    func testFieldsAndKind() async {
        let parts = await resolve(#"widok subject:refinement from:anna with:"Jon Nest" type:event"#)
        XCTAssertEqual(parts.text, "widok")
        XCTAssertEqual(parts.subject, "refinement")
        XCTAssertEqual(parts.organizer, "anna")
        XCTAssertEqual(parts.attendee, "Jon Nest")
        XCTAssertEqual(parts.kind, .event)
        XCTAssertFalse(parts.includesTasks)
        XCTAssertEqual(parts.label, "from anna · with Jon Nest · Events")
    }

    func testFromMeIsTheUsersOwnAndKeepsTasks() async {
        let parts = await resolve("from:Me")
        XCTAssertTrue(parts.organizedByMe)
        XCTAssertNil(parts.organizer)
        XCTAssertTrue(parts.isSearchable, "alone: all of my own")
        XCTAssertTrue(parts.includesTasks, "tasks are the user's own")
        XCTAssertEqual(parts.label, "from me")
    }

    func testDayAcceptsISOAndNaturalDates() async {
        let iso = await resolve("day:2026-10-15")
        XCTAssertEqual(iso.interval, DateInterval(start: day(2026, 10, 15), end: day(2026, 10, 16)))
        XCTAssertTrue(iso.isSearchable, "a date operator searches without words")
        let tomorrow = await resolve("standup day:tomorrow")
        XCTAssertEqual(tomorrow.interval?.start, day(2026, 10, 4))
        XCTAssertEqual(tomorrow.text, "standup")
        let quoted = await resolve(#"day:"next friday""#)
        XCTAssertEqual(quoted.interval?.start, day(2026, 10, 9))
    }

    func testBeforeIsExclusiveAfterInclusiveBetweenIncludesBothEnds() async {
        let before = await resolve("invoice before:2026-10-01")
        XCTAssertEqual(before.interval?.end, day(2026, 10, 1))
        XCTAssertEqual(before.interval?.start, .distantPast)
        let after = await resolve("invoice after:2026-09-01")
        XCTAssertEqual(after.interval?.start, day(2026, 9, 1))
        let between = await resolve("between:2026-09-01..2026-09-30")
        XCTAssertEqual(between.interval, DateInterval(start: day(2026, 9, 1), end: day(2026, 10, 1)))
        let both = await resolve("after:2026-09-01 before:2026-09-10")
        XCTAssertEqual(both.interval, DateInterval(start: day(2026, 9, 1), end: day(2026, 9, 10)), "they intersect")
    }

    func testInvalidValuesAreIgnored() async {
        let parts = await resolve("plan day:someday between:2026-09-30..2026-09-01 type:meeting before:2026-02-31")
        XCTAssertNil(parts.interval)
        XCTAssertNil(parts.kind)
        XCTAssertFalse(parts.hasExplicitDate)
        XCTAssertEqual(parts.text, "plan")
    }

    func testADatePhraseInTheWordsStillNarrowsUnlessAnOperatorSetsTheDate() async {
        let phrase = await resolve("standup tomorrow")
        XCTAssertEqual(phrase.text, "standup")
        XCTAssertEqual(phrase.interval?.start, day(2026, 10, 4))
        XCTAssertFalse(SearchQueryParts(text: "", interval: phrase.interval).isSearchable, "a date phrase alone is Go to's")
        let explicit = await resolve("standup tomorrow day:2026-10-15")
        XCTAssertEqual(explicit.text, "standup tomorrow")
        XCTAssertEqual(explicit.interval?.start, day(2026, 10, 15))
    }
}

@MainActor
final class SearchSessionOperatorTests: XCTestCase {
    private func task(_ title: String, notes: String? = nil, due: Date? = nil) -> TaskItem {
        TaskItem(id: title, title: title, notes: notes, listID: "l", dueDate: due)
    }

    func testTaskMatchingFollowsWordsSubjectAndDates() {
        let now = Date()
        let invoice = task("Pay invoice", notes: "refinement", due: now.addingTimeInterval(-86400))
        XCTAssertTrue(SearchSession.matches(invoice, SearchQueryParts(text: "invoice")))
        XCTAssertTrue(SearchSession.matches(invoice, SearchQueryParts(text: "refinement")), "notes count for words")
        XCTAssertFalse(SearchSession.matches(invoice, SearchQueryParts(text: "", subject: "refinement")), "subject: is title only")
        XCTAssertTrue(SearchSession.matches(invoice, SearchQueryParts(text: "", subject: "invoice")))
        let past = DateInterval(start: .distantPast, end: now)
        XCTAssertTrue(SearchSession.matches(invoice, SearchQueryParts(text: "invoice", interval: past)))
        XCTAssertFalse(SearchSession.matches(invoice, SearchQueryParts(text: "invoice", interval: DateInterval(start: now, duration: 86400))))
    }

    func testOperatorsChooseWhatIsSearched() async {
        let session = SearchSession()
        session.debounce = .zero
        var searchedEvents = false
        session.searchMatches = { _ in searchedEvents = true; return [] }
        session.tasks = { [TaskItem(id: "t", title: "Invoice", listID: "l")] }
        session.parseQuery = { await SearchQueryResolver.resolve($0, referenceDate: Date(), calendar: .current) }

        session.update(query: "invoice type:task")
        await session.settle()
        XCTAssertFalse(searchedEvents, "type:task leaves events out")
        XCTAssertEqual(session.total, 1)

        session.update(query: "invoice from:anna")
        await session.settle()
        XCTAssertTrue(searchedEvents)
        XCTAssertEqual(session.total, 0, "tasks have no organizer")
    }
}

@MainActor
final class SearchPaletteOperatorTests: XCTestCase {
    func testOperatorsMakeItASearchNotGoToOrCreate() async {
        var resolvedDate = false
        let model = SearchPaletteModel(resolveDate: { text, _, _ in resolvedDate = true; return .jumpToDate(Date()) },
                                       resolveTask: { _, _, _, _, _ in nil })
        model.update(query: "standup day:tomorrow")
        await model.settle()
        XCTAssertFalse(resolvedDate)
        XCTAssertFalse(model.actions.contains { $0.kind == .goToDate })
    }
}
