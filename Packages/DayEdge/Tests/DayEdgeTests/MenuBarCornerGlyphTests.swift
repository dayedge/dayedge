import XCTest
@testable import Shell

final class MenuBarCornerGlyphTests: XCTestCase {
    private func resolve(overflow: Bool = false, tasks: Bool = false, paused: Bool = false) -> MenuBarCornerGlyph? {
        MenuBarCornerGlyph.resolve(MenuBarCornerGlyphInputs(isOverflow: overflow, hasTasksDueToday: tasks,
                                                            areAlertsPaused: paused))
    }

    func testNoGlyphWithoutOverflow() {
        XCTAssertNil(resolve())
    }

    func testOverflowShowsPlus() {
        XCTAssertEqual(resolve(overflow: true), .overflow)
    }

    func testTasksDueShowsRing() {
        XCTAssertEqual(resolve(tasks: true), .tasksDue)
    }

    func testPausedAlertsShowPause() {
        XCTAssertEqual(resolve(paused: true), .alertsPaused)
    }

    func testPausedAlertsWinOverTasksDueAndOverflow() {
        XCTAssertEqual(resolve(overflow: true, tasks: true, paused: true), .alertsPaused)
    }

    func testTasksDueWinsOverOverflow() {
        XCTAssertEqual(resolve(overflow: true, tasks: true), .tasksDue)
    }
}
