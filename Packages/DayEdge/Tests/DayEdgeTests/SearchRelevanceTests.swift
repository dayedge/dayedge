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
