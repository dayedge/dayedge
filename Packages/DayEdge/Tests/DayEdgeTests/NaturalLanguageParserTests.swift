import XCTest
import TimeWhisper
@testable import Domain
@testable import Intelligence

private enum ParserFixture {
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        value.locale = Locale(identifier: "pl_PL")
        value.firstWeekday = 2
        return value
    }
    static func date(_ day: Int, _ hour: Int = 0, month: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }
    static let now = date(23, 12)
    static let sources = [CalendarSource(id: "work", title: "Work", tint: .blue)]
    static func parser(language: String = "en") -> NaturalLanguageParser {
        NaturalLanguageParser(language: language, spellCheckerFactory: { NoSpellChecker() })
    }
}

final class NaturalLanguageParserTests: XCTestCase {
    private typealias F = ParserFixture

    func testDefaultEnglishDoesNotFollowPolishLocale() async throws {
        let found = await F.parser().findTemporal("tomorrow", referenceDate: F.now, calendar: F.calendar)
        XCTAssertEqual(found?.temporal.start.date, F.date(24))
    }

    func testDefaultEnglishDoesNotRecognizePolish() async {
        let found = await F.parser().findTemporal("jutro", referenceDate: F.now, calendar: F.calendar)
        XCTAssertNil(found)
    }

    func testPolishCanBeSelectedAtTheEntryPoint() async {
        let found = await F.parser(language: "pl").findTemporal("jutro", referenceDate: F.now, calendar: F.calendar)
        XCTAssertEqual(found?.temporal.start.date, F.date(24))
    }

    func testTaskKeepsDateOnlyDueAndDestination() async throws {
        let values = await F.parser().parse("pay rent tomorrow #work !!!", referenceDate: F.now,
                                            calendar: F.calendar, lists: F.sources, calendars: F.sources)
        guard case .task(let task) = try XCTUnwrap(values.first) else { return XCTFail("Expected task") }
        XCTAssertEqual(task.title, "Pay rent")
        XCTAssertEqual(task.dueDate, F.date(24))
        XCTAssertFalse(task.hasDueTime)
        XCTAssertEqual(task.listID, "work")
        XCTAssertEqual(task.priority, .high)
    }

    func testTimedEventKeepsExclusiveEndAndCalendar() async throws {
        let values = await F.parser().parse("demo tomorrow 15:00-16:00 #work t:e", referenceDate: F.now,
                                            calendar: F.calendar, lists: F.sources, calendars: F.sources)
        guard case .event(let event) = try XCTUnwrap(values.first) else { return XCTFail("Expected event") }
        XCTAssertEqual(event.start, F.date(24, 15))
        XCTAssertEqual(event.end, F.date(24, 16))
        XCTAssertEqual(event.calendarIdentifier, "work")
        XCTAssertFalse(event.isAllDay)
    }

    func testAllDayEventKeepsExclusiveEnd() throws {
        let value = Candidate(content: .event(EventSpec(title: "Conference", time: .allDay(
            startDate: CivilDate(year: 2026, month: 9, day: 24), endDateExclusive: CivilDate(year: 2026, month: 9, day: 27)))))
        guard case .event(let event) = try QuickAddCandidate(value, calendar: F.calendar) else { return XCTFail("Expected event") }
        XCTAssertEqual(event.end, F.date(27))
        let edit = EventQuickAddEdit(draft: event, calendar: F.calendar)
        XCTAssertEqual(edit.lastDay, F.date(26))
        XCTAssertEqual(edit.eventDraft(calendar: F.calendar), event)
    }

    func testMappingPreservesAnExplicitInstant() throws {
        let instant = Moment(date: F.date(24, 17), timeZoneID: "UTC", offsetSeconds: 0)
        let value = Candidate(content: .task(TaskSpec(title: "Call", due: .atTime(instant))))
        guard case .task(let task) = try QuickAddCandidate(value, calendar: F.calendar) else { return XCTFail("Expected task") }
        XCTAssertEqual(task.dueDate, instant.date)
        XCTAssertTrue(task.hasDueTime)
    }

    func testRecurrenceUsesFoundationWeekdayNumbering() throws {
        let rule = RecurrenceSpec(frequency: .weekly, interval: 2, weekdays: [WeekdayRule(day: .monday)])
        let value = Candidate(content: .task(TaskSpec(title: "Review", recurrence: rule, reminder: .before(minutes: 15))))
        guard case .task(let task) = try QuickAddCandidate(value, calendar: F.calendar) else { return XCTFail("Expected task") }
        XCTAssertEqual(task.recurrenceRule?.weekdays, [.init(weekday: 2)])
        XCTAssertEqual(task.recurrenceRule?.interval, 2)
        XCTAssertEqual(task.alert, .relative(minutesBefore: 15))
    }

    func testReleaseAllowsReuse() async {
        let parser = F.parser()
        _ = await parser.findTemporal("tomorrow", referenceDate: F.now, calendar: F.calendar)
        await parser.releaseResources()
        let found = await parser.findTemporal("tomorrow", referenceDate: F.now, calendar: F.calendar)
        XCTAssertEqual(found?.temporal.start.date, F.date(24))
    }

    func testImpossibleDateIsNotNavigation() async {
        let found = await F.parser().findTemporal("2026-02-31", referenceDate: F.now, calendar: F.calendar)
        XCTAssertNil(found)
    }

    func testMonthCanNavigateWithoutADay() async throws {
        let result = await find("March")
        let found = try XCTUnwrap(result)
        XCTAssertEqual(TemporalPresentation.navigation(found, calendar: F.calendar), .jumpToMonth(F.date(1, month: 3)))
    }

    func testTextWithDateDoesNotNavigate() async throws {
        let result = await find("meeting tomorrow")
        let found = try XCTUnwrap(result)
        XCTAssertEqual(found.remainingText, "meeting")
        XCTAssertNil(TemporalPresentation.navigation(found, calendar: F.calendar))
    }

    func testSearchTimePointBecomesTheLocalDay() async throws {
        let result = await find("tomorrow at 9am")
        let found = try XCTUnwrap(result)
        XCTAssertEqual(TemporalPresentation.interval(found.temporal, calendar: F.calendar),
                       DateInterval(start: F.date(24), end: F.date(25)))
    }

    func testSearchDayAcrossDSTIsNotTwentyFourHours() async throws {
        let result = await find("2026-10-25")
        let found = try XCTUnwrap(result)
        XCTAssertEqual(TemporalPresentation.interval(found.temporal, calendar: F.calendar).duration, 25 * 3600)
    }

    private func find(_ text: String) async -> FoundTemporal? {
        await F.parser().findTemporal(text, referenceDate: F.now, calendar: F.calendar)
    }
}

@MainActor
final class WhisperPaletteTests: XCTestCase {
    private typealias F = ParserFixture

    private func model() -> SearchPaletteModel {
        let parser = F.parser()
        let model = SearchPaletteModel(findTemporal: { text, now, calendar in
            await parser.findTemporal(text, referenceDate: now, calendar: calendar)
        }, parse: { text, now, calendar, lists, calendars in
            await parser.parse(text, referenceDate: now, calendar: calendar, lists: lists, calendars: calendars)
        })
        model.now = { F.now }
        model.calendar = F.calendar
        model.taskLists = { F.sources }
        model.eventCalendars = { F.sources }
        model.results.debounce = .zero
        return model
    }

    func testDateOnlyOffersNavigationInsteadOfCreation() async {
        let model = model()
        model.update(query: "tomorrow")
        await model.settle()
        XCTAssertEqual(model.actions.map(\.kind), [.goToDate, .search, .askAI])
    }

    func testTitleWithDateOffersCreationInsteadOfNavigation() async {
        let model = model()
        model.update(query: "meeting tomorrow")
        await model.settle()
        XCTAssertEqual(model.actions.map(\.kind), [.createTask, .createEvent, .search, .askAI])
    }

    func testPlainTextOffersSearchAndAsk() async {
        let model = model()
        model.update(query: "architecture")
        await model.settle()
        XCTAssertEqual(model.actions.map(\.kind), [.search, .askAI])
    }

    func testMissingDestinationsHideCreation() async {
        let model = model()
        model.taskLists = { [] }
        model.eventCalendars = { [] }
        model.update(query: "meeting tomorrow")
        await model.settle()
        XCTAssertEqual(model.actions.map(\.kind), [.search, .askAI])
    }

    func testCancelledOlderResolutionCannotReplaceNewActions() async {
        let gate = ParserGate()
        let model = SearchPaletteModel(findTemporal: { _, _, _ in nil }, parse: { text, _, _, _, _ in
            if text == "old" { await gate.wait() }
            return [.task(TaskDraft(title: text))]
        })
        model.taskLists = { F.sources }
        model.update(query: "old")
        let oldResolution = model.resolution
        await gate.waitUntilStarted()
        model.update(query: "new")
        await model.settle()
        await gate.resume()
        await oldResolution?.value
        XCTAssertEqual(model.taskDraft?.title, "new")
    }

    func testSearchReusesResolvedTemporalResult() async {
        let model = model()
        model.results.parseQuery = { _ in XCTFail("Already resolved"); return .plain("") }
        model.update(query: "meeting tomorrow")
        await model.settle()
        await model.results.settle()
        XCTAssertEqual(model.results.parts.text, "meeting")
        XCTAssertEqual(model.results.parts.interval, DateInterval(start: F.date(24), end: F.date(25)))
    }
}

private actor ParserGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
