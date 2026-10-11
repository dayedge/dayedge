import XCTest
@testable import Shell

final class MenuBarCornerGlyphTests: XCTestCase {
    private func resolve(overflow: Bool = false, tasks: Bool = false) -> MenuBarCornerGlyph? {
        MenuBarCornerGlyph.resolve(MenuBarCornerGlyphInputs(isOverflow: overflow, hasTasksDueToday: tasks))
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

    func testTasksDueWinsOverOverflow() {
        XCTAssertEqual(resolve(overflow: true, tasks: true), .tasksDue)
    }
}
