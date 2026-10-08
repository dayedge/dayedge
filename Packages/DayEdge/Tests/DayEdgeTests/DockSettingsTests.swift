import XCTest
@testable import Shell

final class DockSettingsTests: XCTestCase {
    func testOffByDefaultAndFollowsTheStoredChoice() {
        let defaults = UserDefaults(suiteName: "DockSettingsTests-\(UUID())")!
        XCTAssertFalse(DockSettings.showsIcon(defaults: defaults), "a menu-bar app: not in the Dock unless asked")
        defaults.set(true, forKey: DockSettings.showsIconKey)
        XCTAssertTrue(DockSettings.showsIcon(defaults: defaults))
    }
}
