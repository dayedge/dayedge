import XCTest
@testable import Shell

final class MenuBarCornerBadgeTests: XCTestCase {
    private func resolve(events: Int, tasks: Bool = false) -> MenuBarCornerBadge? {
        MenuBarCornerBadge.resolve(MenuBarCornerBadgeInputs(badgeValue: events, hasTasksDueToday: tasks))
    }

    func testNoBadgeUpToNine() {
        XCTAssertNil(resolve(events: 0))
        XCTAssertNil(resolve(events: 9))
    }

    func testOverflowAboveNine() {
        XCTAssertEqual(resolve(events: 10), .overflow)
    }

    func testTasksDueShowsRing() {
        XCTAssertEqual(resolve(events: 0, tasks: true), .tasksDue)
    }

    func testTasksDueWinsOverOverflow() {
        XCTAssertEqual(resolve(events: 12, tasks: true), .tasksDue)
    }
}
