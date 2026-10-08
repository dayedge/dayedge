import XCTest
@testable import Shell
@testable import Domain
@testable import Intelligence

final class SearchRelevanceTests: XCTestCase {
    func testTiers() {
        XCTAssertEqual(SearchRelevance.tier(title: "Sprint Refinement", query: "sprint refinement"), .exactTitle)
        XCTAssertEqual(SearchRelevance.tier(title: "Q3 Sprint Refinement", query: "sprint refinement"), .titlePhrase)
        XCTAssertEqual(SearchRelevance.tier(title: "Refinement of the sprint", query: "sprint refinement"), .titleWords)
        XCTAssertEqual(SearchRelevance.tier(title: "Planning", query: "sprint refinement"), .elsewhere)
        XCTAssertEqual(SearchRelevance.tier(title: "Café  Meetup", query: "cafe meetup"), .exactTitle)
    }

    func testTierFirstThenWhereBrowsingStartsThenScore() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_791_028_800)  // 3 Oct 2026, noon UTC
        func ranked(_ id: Int64, _ title: String, rank: Double, days: Double) -> RankedMatch {
            RankedMatch(match: SearchMatch(id: id, start: now.addingTimeInterval(days * 86400), isAllDay: false), title: title, rank: rank)
        }
        let events = [
            ranked(1, "Lunch", rank: -9, days: 1),               // people only, best score, tomorrow
            ranked(2, "Refinement", rank: -2, days: -700),       // exact title, long ago
            ranked(3, "Team refinement", rank: -8, days: -2),    // phrase, past, better score
            ranked(4, "Team refinement", rank: -3, days: 30),    // phrase, upcoming
            ranked(5, "Team refinement", rank: -3, days: 2),     // phrase, sooner
        ]
        let top = SearchRelevance.top(events: events, tasks: [], query: "refinement", now: now, limit: 5, calendar: calendar)
        XCTAssertEqual(top.compactMap(\.eventID), [2, 5, 4, 3, 1],
                       "tier first; then upcoming soonest, then the most recent past — never by score alone")
    }
}

final class SearchDateFilterTests: XCTestCase {
    private var dates: DatePresentationFormatter { DatePresentationFormatter(regionalLocale: Locale(identifier: "en_GB"), displayLocale: Locale(identifier: "en"), calendar: calendar) }
    private let reference = Date(timeIntervalSince1970: 1_791_028_800)  // 3 Oct 2026, noon UTC
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }

    private func span(_ query: String, _ phrase: String, _ date: DateComponents, day: Bool, month: Bool = true) -> ChronoSpan {
        let range = (query as NSString).range(of: phrase)
        return ChronoSpan(utf16Offset: range.location, utf16Length: range.length, date: date,
                          isDayCertain: day, isTimeCertain: false, isMonthCertain: month, end: nil)
    }

    func testDaySplitsOffAsThatDay() {
        let query = "standup tomorrow"
        let parts = SearchDateFilter.split(query, spans: [span(query, "tomorrow", DateComponents(year: 2026, month: 10, day: 4), day: true)],
                                           referenceDate: reference, calendar: calendar, dates: dates)
        XCTAssertEqual(parts.text, "standup")
        XCTAssertEqual(parts.interval?.start, calendar.date(from: DateComponents(year: 2026, month: 10, day: 4)))
        XCTAssertEqual(parts.interval?.duration, 86400)
        XCTAssertEqual(parts.label, "Sun 4 Oct")
    }

    func testMonthSplitsOffAsTheWholeMonth() {
        let query = "refinement last March notes"
        let parts = SearchDateFilter.split(query, spans: [span(query, "March", DateComponents(year: 2027, month: 3, day: 1), day: false)],
                                           referenceDate: reference, calendar: calendar)
        XCTAssertEqual(parts.text, "refinement notes")
        XCTAssertEqual(parts.interval?.start, calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)))
        XCTAssertEqual(parts.interval?.end, calendar.date(from: DateComponents(year: 2026, month: 4, day: 1)))
        XCTAssertEqual(parts.label, "March 2026")
    }

    func testMonthModifiersPickTheYear() {
        func start(_ query: String, _ month: Int) -> Date? {
            SearchDateFilter.split(query, spans: [span(query, query.components(separatedBy: " ").last!, DateComponents(year: 2027, month: month, day: 1), day: false)],
                                   referenceDate: reference, calendar: calendar).interval?.start
        }
        func first(_ year: Int, _ month: Int) -> Date? { calendar.date(from: DateComponents(year: year, month: month, day: 1)) }
        XCTAssertEqual(start("sync March", 3), first(2026, 3), "a bare month is this year's")
        XCTAssertEqual(start("sync last November", 11), first(2025, 11))
        XCTAssertEqual(start("sync next March", 3), first(2027, 3))
        XCTAssertEqual(start("sync next December", 12), first(2026, 12))
    }

    func testUncertainOrInWordPhrasesStayText() {
        let vague = "review 2027"
        XCTAssertEqual(SearchDateFilter.split(vague, spans: [span(vague, "2027", DateComponents(year: 2027), day: false, month: false)],
                                              referenceDate: reference, calendar: calendar), .plain(vague))
        let inWord = "Mayday drill"
        XCTAssertEqual(SearchDateFilter.split(inWord, spans: [span(inWord, "May", DateComponents(year: 2026, month: 5), day: false)],
                                              referenceDate: reference, calendar: calendar), .plain(inWord))
    }
}

@MainActor
final class SearchSessionDateFilterTests: XCTestCase {
    private let base = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3600)

    private func session(interval: DateInterval?, text: String) -> (SearchSession, Box) {
        let box = Box()
        let session = SearchSession()
        session.debounce = .zero
        session.parseQuery = { _ in SearchQueryParts(text: text, interval: interval, label: interval == nil ? nil : "March") }
        session.searchMatches = { [base] parts in
            box.searched = (parts.text, parts.interval)
            let filter = parts.interval
            return (-40..<40).map { SearchMatch(id: Int64($0 + 40), start: base.addingTimeInterval(Double($0) * 86400), isAllDay: false) }
                .filter { match in filter.map { $0.start <= match.start && match.start < $0.end } ?? true }
        }
        session.loadEvents = { [base] ids in
            Dictionary(uniqueKeysWithValues: ids.map {
                ($0, AgendaEventModel(id: "e\($0)", startTime: "09:00", endTime: "10:00",
                                      startDate: base.addingTimeInterval(Double(Int($0) - 40) * 86400), title: "Daily"))
            })
        }
        return (session, box)
    }

    final class Box { var searched: (String, DateInterval?)? }

    func testDateFilteredQueryOpensAtTheFirstMatchingDay() async {
        let filter = DateInterval(start: base.addingTimeInterval(-30 * 86400), duration: 10 * 86400)
        let (session, box) = session(interval: filter, text: "daily")
        session.update(query: "daily last month")
        await session.settle()
        XCTAssertEqual(box.searched?.0, "daily")
        XCTAssertEqual(box.searched?.1, filter)
        XCTAssertEqual(session.total, 10)
        XCTAssertEqual(session.index.anchorDayIndex, 0, "opens at the first matching day, not today")
        XCTAssertEqual(session.summary, "10 results · March")
    }

    func testDateOnlyQueryDoesntSearch() async {
        let (session, box) = session(interval: DateInterval(start: base, duration: 86400), text: "")
        session.update(query: "tomorrow")
        await session.settle()
        XCTAssertNil(box.searched)
        XCTAssertEqual(session.total, 0)
    }

    func testRankedPreviewReplacesNearestToday() async {
        let (session, _) = session(interval: nil, text: "daily")
        session.searchRanked = { [base] _ in
            [RankedMatch(match: SearchMatch(id: 2, start: base.addingTimeInterval(-38 * 86400), isAllDay: false), title: "Daily", rank: -5),
             RankedMatch(match: SearchMatch(id: 50, start: base.addingTimeInterval(10 * 86400), isAllDay: false), title: "Other", rank: -9)]
        }
        session.update(query: "daily")
        await session.settle()
        XCTAssertEqual(session.preview.map(\.id), ["event:e2", "event:e50"], "the exact title first, even 38 days ago")
    }
}

/// The real chrono parse behind the split.
final class SearchDateFilterChronoTests: XCTestCase {
    func testChronoPhrases() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let reference = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 12))!
        let tomorrow = await SearchDateFilter.parse("standup tomorrow", referenceDate: reference, calendar: calendar)
        XCTAssertEqual(tomorrow.text, "standup")
        XCTAssertEqual(tomorrow.interval?.start, calendar.date(from: DateComponents(year: 2026, month: 10, day: 4)))
        let march = await SearchDateFilter.parse("refinement last March", referenceDate: reference, calendar: calendar)
        XCTAssertEqual(march.text, "refinement")
        XCTAssertEqual(march.interval?.start, calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)))
        XCTAssertEqual(march.interval?.end, calendar.date(from: DateComponents(year: 2026, month: 4, day: 1)))
        let plain = await SearchDateFilter.parse("refinement", referenceDate: reference, calendar: calendar)
        XCTAssertEqual(plain, .plain("refinement"))
    }
}
