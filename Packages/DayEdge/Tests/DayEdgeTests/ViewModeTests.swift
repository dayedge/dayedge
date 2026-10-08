import XCTest
@testable import Shell
@testable import Domain
@testable import UI

final class ViewModeTests: XCTestCase {
    func testAskIsTheFourthPeerView() {
        XCTAssertEqual(ViewMode.allCases, [.month, .day, .tasks, .ask])
        XCTAssertEqual(ViewMode.ask.symbolName, "sparkles")
        XCTAssertEqual(ViewMode.ask.tooltipTitle, "Ask DayEdge")
        XCTAssertEqual(ShortcutCommand.viewMode(.ask).defaultShortcut?.displayLabel, KeyboardCommand(key: "4").displayLabel)
        XCTAssertEqual(ViewMode(settingsValue: ViewMode.ask.settingsValue), .ask)
    }
}
