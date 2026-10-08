import XCTest
@testable import Shell
@testable import Intelligence

final class SearchDayPagingTests: XCTestCase {
    typealias P = SearchDayPaging

    func testOpensAroundWhereBrowsingStarts() {
        XCTAssertEqual(P.opening(at: 1000, dayCount: 3000), 993..<1021, "years of days: only the agenda's 7 + 21")
        XCTAssertEqual(P.opening(at: 3, dayCount: 3000), 0..<24)
        XCTAssertEqual(P.opening(at: 2995, dayCount: 3000), 2988..<3000)
        XCTAssertEqual(P.opening(at: nil, dayCount: 20), 0..<20)
        XCTAssertEqual(P.opening(at: 5, dayCount: 0), 0..<0)
    }

    func testStaysPutWhereItOpensAndAwayFromTheEdges() {
        XCTAssertNil(P.paged(993..<1021, visible: 1000...1005, dayCount: 3000), "at rest where it opened")
        XCTAssertNil(P.paged(960..<1040, visible: 990...995, dayCount: 3000))
    }

    func testGrowsAPageTowardTheEdgeNeared() {
        XCTAssertEqual(P.paged(993..<1021, visible: 996...1000, dayCount: 3000), 963..<1021)
        XCTAssertEqual(P.paged(993..<1021, visible: 1010...1015, dayCount: 3000), 993..<1051)
        XCTAssertNil(P.paged(0..<28, visible: 0...4, dayCount: 3000), "nothing before the first day")
        XCTAssertNil(P.paged(2972..<3000, visible: 2995...2999, dayCount: 3000), "nothing after the last")
    }

    func testTrimsTheFarSidePastTheLimit() {
        let up = P.paged(930..<1020, visible: 932...937, dayCount: 3000)!
        XCTAssertEqual(up, 900..<960, "grown a page, trimmed back to 60")
        XCTAssertTrue(up.contains(937), "what's on screen stays")
        let down = P.paged(930..<1020, visible: 1010...1016, dayCount: 3000)!
        XCTAssertEqual(down, 990..<1050)
        XCTAssertTrue(down.contains(1010))
    }

    func testSelectionFarAwayReopensTheWindowThere() {
        XCTAssertEqual(P.showing(1000, in: 993..<1021, dayCount: 3000), 993..<1021)
        XCTAssertEqual(P.showing(2500, in: 993..<1021, dayCount: 3000), 2493..<2521)
    }
}

final class ChatTranscriptPagingTests: XCTestCase {
    typealias P = ChatTranscriptPaging

    func testOpensOnTheNewestRows() {
        XCTAssertEqual(P.paging.opening(at: 0, count: 1000), 0..<80)
        XCTAssertEqual(P.paging.opening(at: 0, count: 30), 0..<30)
    }

    func testPagesDownIntoOlderAnswersAndTrimsTheNewestPastTheLimit() {
        XCTAssertNil(P.paging.paged(0..<80, visible: 10...30, count: 1000), "reading the newest")
        XCTAssertEqual(P.paging.paged(0..<80, visible: 60...70, count: 1000), 0..<140)
        let far = P.paging.paged(0..<200, visible: 185...195, count: 1000)!
        XCTAssertEqual(far.count, P.paging.trimmedTo, "past the limit the newest rows go")
        XCTAssertTrue(far.contains(185))
    }

    func testFollowsRowsAddedAtTheTop() {
        XCTAssertEqual(P.adjusted(0..<80, delta: 12, count: 300, followsTop: true), 0..<92, "at the newest: grows with them")
        XCTAssertEqual(P.adjusted(100..<200, delta: 12, count: 312, followsTop: false), 112..<212, "further down: the same rows stay")
        XCTAssertEqual(P.adjusted(0..<20, delta: 5, count: 25, followsTop: true), 0..<25)
        XCTAssertEqual(P.adjusted(0..<80, delta: -500, count: 10, followsTop: true), 0..<10, "a shorter conversation: clamped")
        XCTAssertEqual(P.adjusted(50..<90, delta: 0, count: 0, followsTop: false), 0..<0)
    }

    func testInsertionsAtTheTopRemainBoundedWithoutTruncatingHistory() {
        var window = 0..<80
        var count = 80
        for _ in 0..<100 {
            count += 50
            window = P.adjusted(window, delta: 50, count: count, followsTop: true)
            XCTAssertLessThanOrEqual(window.count, 200)
        }
        XCTAssertEqual(window, 0..<200)
        var visible = window
        while visible.upperBound < count {
            visible = P.paged(visible, visible: (visible.upperBound - 5)...(visible.upperBound - 1), count: count)!
        }
        XCTAssertTrue(visible.contains(count - 1), "all older rows remain reachable")
    }

    func testReadingBelowTheTopUsesStableAnchorShiftRatherThanInsertionCount() {
        XCTAssertEqual(P.adjusted(0..<180, delta: 50, count: 1_000, followsTop: false,
                                  anchorShift: 0, visible: 100...110), 0..<180,
                       "new rows appended later inside the newest answer did not move this reader")
        XCTAssertEqual(P.adjusted(0..<180, delta: 50, count: 1_000, followsTop: false,
                                  anchorShift: 12, visible: 112...122), 12..<192)
        let oversized = P.adjusted(0..<400, delta: 0, count: 1_000, followsTop: false, visible: 350...360)
        XCTAssertEqual(oversized.count, 200)
        XCTAssertTrue(oversized.contains(350) && oversized.contains(360))
    }

    func testExceptionalViewportKeepsOnlyItsVisibleRows() {
        let next = P.paged(0..<500, visible: 100...350, count: 1_000)!
        XCTAssertEqual(next, 100..<351)
        XCTAssertEqual(next.count, 251, "viewport exception cannot retain the rest of history")
    }
}
