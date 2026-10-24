import XCTest
import TimeWhisper
import os
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
        NaturalLanguageParser(language: { language })
    }
    /// What the library would find for the palette tests' queries, fixed so they test the palette, not the tagger.
    static func found(_ text: String) -> FoundDate? {
        let tomorrow = ParsedDate(start: date(24), end: date(25), span: .day)
        switch text {
        case "tomorrow": return FoundDate(date: tomorrow, remainingText: "")
        case "meeting tomorrow": return FoundDate(date: tomorrow, remainingText: "meeting")
        default: return nil
        }
    }
    static func candidates(_ text: String) -> [QuickAddCandidate] {
        guard text == "meeting tomorrow" else { return [] }
        return [.task(TaskDraft(title: "Meeting", dueDate: date(24))),
                .event(EventDraft(title: "Meeting", start: date(24), end: date(25), isAllDay: true))]
    }
}

/// DayEdge's side of TimeWhisper: the calendar and language it passes in, and how the library's answers become the app's
/// drafts and search ranges. How text is read is time-whisper's to test; these use `parseTemporal`, which needs no model,
/// or answers built by hand.
final class NaturalLanguageParserTests: XCTestCase {
    private typealias F = ParserFixture

    func testTheCalendarsRegionDecidesTheDateOrder() async {
        var american = F.calendar
        american.locale = Locale(identifier: "en_US")
        let polish = await F.parser().parseTemporal("11/12/2026", referenceDate: F.now, calendar: F.calendar)
        let us = await F.parser().parseTemporal("11/12/2026", referenceDate: F.now, calendar: american)
        XCTAssertEqual(polish?.start, F.date(11, month: 12))
        XCTAssertEqual(us?.start, F.date(12, month: 11))
    }

    func testTheLanguageIsChosenAtTheEntryPoint() async {
        let english = await F.parser().parseTemporal("jutro", referenceDate: F.now, calendar: F.calendar)
        let polish = await F.parser(language: "pl").parseTemporal("jutro", referenceDate: F.now, calendar: F.calendar)
        XCTAssertNil(english, "the Polish locale does not switch the language")
        XCTAssertEqual(polish?.start, F.date(24))
    }

    /// English only for now; the system's languages and a Settings choice are read once others are supported.
    func testTheLanguageFollowsTheOverrideThenThePreferredLanguages() {
        XCTAssertEqual(ParsingLanguage.current(), "en")
        XCTAssertEqual(ParsingLanguage.resolve(override: nil, preferred: ["pl-PL", "en-GB"]), "en", "only English is read yet")
        XCTAssertEqual(ParsingLanguage.resolve(override: "pl", preferred: []), "en")
        let both = ["en", "pl"]
        XCTAssertEqual(ParsingLanguage.resolve(override: nil, preferred: ["pl-PL", "en-GB"], supported: both), "pl")
        XCTAssertEqual(ParsingLanguage.resolve(override: nil, preferred: ["de-DE", "en-GB"], supported: both), "en")
        XCTAssertEqual(ParsingLanguage.resolve(override: "en", preferred: ["pl-PL"], supported: both), "en", "Settings wins")
        XCTAssertEqual(ParsingLanguage.resolve(override: "de", preferred: ["pl-PL"], supported: both), "pl", "an unread choice is skipped")
        XCTAssertEqual(ParsingLanguage.resolve(override: nil, preferred: ["de-DE"], supported: both), "en", "the first is the fallback")
    }

    func testAChangedLanguageTakesEffectOnTheNextRequest() async {
        let language = OSAllocatedUnfairLock(initialState: "en")
        let parser = NaturalLanguageParser(language: { language.withLock { $0 } })
        let english = await parser.parseTemporal("jutro", referenceDate: F.now, calendar: F.calendar)
        language.withLock { $0 = "pl" }
        let polish = await parser.parseTemporal("jutro", referenceDate: F.now, calendar: F.calendar)
        XCTAssertNil(english)
        XCTAssertEqual(polish?.start, F.date(24))
    }

    func testReleaseAllowsReuse() async {
        let parser = F.parser()
        _ = await parser.parseTemporal("tomorrow", referenceDate: F.now, calendar: F.calendar)
        await parser.releaseResources()
        let again = await parser.parseTemporal("tomorrow", referenceDate: F.now, calendar: F.calendar)
        XCTAssertEqual(again?.start, F.date(24))
    }

    // MARK: Drafts

    func testAllDayEventKeepsExclusiveEnd() throws {
        let value = Candidate(content: .event(EventSpec(title: "Conference", time: .allDay(
            startDate: CivilDate(year: 2026, month: 9, day: 24), endDateExclusive: CivilDate(year: 2026, month: 9, day: 27)))))
        let event = try XCTUnwrap(try QuickAddCandidate(value, calendar: F.calendar).event)
        XCTAssertEqual(event.end, F.date(27))
        let edit = EventQuickAddEdit(draft: event, calendar: F.calendar)
        XCTAssertEqual(edit.timing.lastDay, F.date(26))
        XCTAssertEqual(edit.eventDraft(calendar: F.calendar), event)
    }

    func testMappingPreservesAnExplicitInstant() throws {
        let instant = Moment(date: F.date(24, 17), timeZoneID: "UTC", offsetSeconds: 0)
        let value = Candidate(content: .task(TaskSpec(title: "Call", due: .atTime(instant))))
        let task = try XCTUnwrap(try QuickAddCandidate(value, calendar: F.calendar).task)
        XCTAssertEqual(task.dueDate, instant.date)
        XCTAssertTrue(task.hasDueTime)
    }

    func testRecurrenceUsesFoundationWeekdayNumbering() throws {
        let rule = RecurrenceSpec(frequency: .weekly, interval: 2, weekdays: [WeekdayRule(day: .monday)])
        let value = Candidate(content: .task(TaskSpec(title: "Review", recurrence: rule, reminder: .before(minutes: 15))))
        let task = try XCTUnwrap(try QuickAddCandidate(value, calendar: F.calendar).task)
        XCTAssertEqual(task.recurrenceRule?.weekdays, [.init(weekday: 2)])
        XCTAssertEqual(task.recurrenceRule?.interval, 2)
        XCTAssertEqual(task.alert, .relative(minutesBefore: 15))
    }

    // MARK: Search ranges

    func testAMonthNavigatesWithoutADay() {
        let march = ParsedDate(start: F.date(1, month: 3), end: F.date(1, month: 4), span: .month)
        XCTAssertEqual(TemporalPresentation.navigation(FoundDate(date: march, remainingText: ""), calendar: F.calendar),
                       .jumpToMonth(F.date(1, month: 3)))
    }

    func testTextBesideADateDoesNotNavigate() {
        let found = FoundDate(date: ParsedDate(start: F.date(24), end: F.date(25), span: .day), remainingText: "meeting")
        XCTAssertNil(TemporalPresentation.navigation(found, calendar: F.calendar))
    }

    func testATimePointBecomesItsLocalDay() {
        let nineAM = ParsedDate(start: F.date(24, 9), end: F.date(24, 9), span: .day, hasTime: true)
        XCTAssertEqual(TemporalPresentation.interval(nineAM, calendar: F.calendar), DateInterval(start: F.date(24), end: F.date(25)))
    }

    func testADayAcrossDSTIsNotTwentyFourHours() {
        let changeDay = ParsedDate(start: F.date(25, month: 10), end: F.date(25, month: 10), span: .day, hasTime: true)
        XCTAssertEqual(TemporalPresentation.interval(changeDay, calendar: F.calendar).duration, 25 * 3600)
    }
}

@MainActor
final class SearchPaletteResolutionTests: XCTestCase {
    private typealias F = ParserFixture

    private func model() -> SearchPaletteModel {
        let model = SearchPaletteModel(findTemporal: { text, _, _ in F.found(text) }, parse: { text, _, _, _, _ in F.candidates(text) })
        model.now = { F.now }
        model.calendar = F.calendar
        model.taskLists = { F.sources }
        model.eventCalendars = { F.sources }
        model.results.debounce = .zero
        model.typingPause = .zero
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
        model.typingPause = .zero
        model.update(query: "old")
        let oldResolution = model.resolution
        await gate.waitUntilStarted()
        model.update(query: "new")
        await model.settle()
        await gate.resume()
        await oldResolution?.value
        XCTAssertEqual(model.taskDraft?.title, "new")
    }

    func testFastTypingReadsOnlyTheLastText() async {
        let read = TextLog()
        let model = SearchPaletteModel(findTemporal: { text, _, _ in await read.append(text); return nil },
                                       parse: { _, _, _, _, _ in [] })
        model.typingPause = .milliseconds(20)
        for text in ["m", "me", "mee", "meet"] { model.update(query: text) }
        await model.settle()
        let texts = await read.texts
        XCTAssertEqual(texts, ["meet"], "a keystroke within the pause replaces the one before")
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

/// What a fake parser was asked to read, in order.
private actor TextLog {
    private(set) var texts: [String] = []
    func append(_ text: String) { texts.append(text) }
}
