import XCTest
@testable import Shell

final class MeetingHUDDisplaySelectionTests: XCTestCase {
    func testActiveUsesPointerThenKeyWindowThenMain() {
        let displays: [UInt32] = [10, 20, 30]
        XCTAssertEqual(
            MeetingHUDDisplaySelection.selectedIDs(
                for: .active, availableIDs: displays, pointerID: 30, keyWindowID: 20
            ), [30]
        )
        XCTAssertEqual(
            MeetingHUDDisplaySelection.selectedIDs(
                for: .active, availableIDs: displays, pointerID: nil, keyWindowID: 20
            ), [20]
        )
        XCTAssertEqual(
            MeetingHUDDisplaySelection.selectedIDs(
                for: .active, availableIDs: displays, pointerID: nil, keyWindowID: nil
            ), [10]
        )
    }

    func testMainAndAllPreserveTheirDisplayPolicies() {
        let displays: [UInt32] = [10, 20, 30]
        XCTAssertEqual(
            MeetingHUDDisplaySelection.selectedIDs(
                for: .main, availableIDs: displays, pointerID: 30, keyWindowID: 20
            ), [10]
        )
        XCTAssertEqual(
            MeetingHUDDisplaySelection.selectedIDs(
                for: .all, availableIDs: displays, pointerID: 30, keyWindowID: 20
            ), displays
        )
    }

    func testTakeoverTimerFormatting() {
        XCTAssertEqual(MeetingTakeoverView.timerString(seconds: 42), "00:42")
        XCTAssertEqual(MeetingTakeoverView.timerString(seconds: 4 * 60 + 24), "04:24")
        XCTAssertEqual(MeetingTakeoverView.timerString(seconds: 60 * 60 + 4 * 60 + 24), "1:04:24")
    }

    func testPointerMigrationRequiresStableEntry() {
        var migration = MeetingTakeoverPointerMigration()
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertNil(migration.nextActiveDisplayID(
            currentID: 10, pointerID: 20, isClearlyInside: true, now: start
        ))
        XCTAssertNil(migration.nextActiveDisplayID(
            currentID: 10, pointerID: 20, isClearlyInside: true,
            now: start.addingTimeInterval(0.15)
        ))
        XCTAssertEqual(migration.nextActiveDisplayID(
            currentID: 10, pointerID: 20, isClearlyInside: true,
            now: start.addingTimeInterval(0.21)
        ), 20)
    }

    func testBoundaryJitterCancelsPendingMigration() {
        var migration = MeetingTakeoverPointerMigration()
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertNil(migration.nextActiveDisplayID(
            currentID: 10, pointerID: 20, isClearlyInside: true, now: start
        ))
        XCTAssertNil(migration.nextActiveDisplayID(
            currentID: 10, pointerID: 20, isClearlyInside: false,
            now: start.addingTimeInterval(0.1)
        ))
        XCTAssertNil(migration.nextActiveDisplayID(
            currentID: 10, pointerID: 20, isClearlyInside: true,
            now: start.addingTimeInterval(0.21)
        ), "re-entry must start a fresh dwell")
    }
}
