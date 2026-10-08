import XCTest
@testable import Shell

final class MeetingReminderChoicesTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testBeforeStart() {
        let choices = MeetingReminderChoices.resolve(start: start, now: start.addingTimeInterval(-1))
        XCTAssertEqual(choices.primary, .untilStart)
        XCTAssertEqual(choices.primaryTitle, "Remind at start")
        XCTAssertEqual(choices.menu, [.untilStart, .minutes(1), .minutes(5), .minutes(10), .custom])
        XCTAssertEqual(choices.menu.map(\.menuTitle), [
            "Remind at start", "In 1 minute", "In 5 minutes", "In 10 minutes", "Custom…"
        ])
    }

    func testAtStart() {
        let choices = MeetingReminderChoices.resolve(start: start, now: start)
        XCTAssertEqual(choices.primary, .minutes(1))
        XCTAssertEqual(choices.primaryTitle, "Remind in 1 min")
        XCTAssertEqual(choices.menu, [.minutes(1), .minutes(5), .minutes(10), .minutes(15), .custom])
        XCTAssertEqual(choices.menu.map(\.menuTitle), [
            "In 1 minute", "In 5 minutes", "In 10 minutes", "In 15 minutes", "Custom…"
        ])
    }
}
