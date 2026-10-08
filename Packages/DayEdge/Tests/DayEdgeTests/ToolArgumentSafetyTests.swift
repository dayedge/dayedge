import XCTest
@testable import Intelligence
@testable import Platform

/// What a model sends is untrusted: no number may trap, no lookup may wander.
final class ToolArgumentSafetyTests: XCTestCase {
    func testNumbersAreClampedNeverTrapping() {
        func integer(_ value: Double) -> Int? {
            AssistantToolArguments(["n": .number(value)]).integer("n", in: 5...1440)
        }
        XCTAssertEqual(integer(1e300), 1440)
        XCTAssertEqual(integer(-1e300), 5)
        XCTAssertNil(integer(.nan))
        XCTAssertNil(integer(.infinity))
        XCTAssertEqual(integer(0), 5)
        XCTAssertEqual(integer(90.6), 91)
        XCTAssertNil(AssistantToolArguments(["n": .string("30")]).integer("n", in: 5...1440))
        XCTAssertNil(AssistantToolArguments().integer("n", in: 5...1440))
    }

    func testTheSeriesIsTheOneInTheOccurrencesCalendar() {
        typealias Candidate = EventKitEventEditor.SeriesCandidate
        let candidates = [
            Candidate(calendarID: "other-account", itemID: "A", repeats: true),
            Candidate(calendarID: "work", itemID: "B", repeats: false),
            Candidate(calendarID: "work", itemID: "C", repeats: true),
            Candidate(calendarID: "work", itemID: "A", repeats: true)
        ]
        XCTAssertEqual(EventKitEventEditor.seriesIndex(in: candidates, calendarID: "work", itemID: "A"), 3, "same item wins")
        XCTAssertEqual(EventKitEventEditor.seriesIndex(in: candidates, calendarID: "work", itemID: "Z"), 2, "else the calendar's series")
        XCTAssertNil(EventKitEventEditor.seriesIndex(in: candidates, calendarID: "home", itemID: "A"), "never another calendar's")
    }
}
