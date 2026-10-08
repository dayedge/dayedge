import XCTest
@testable import Shell
@testable import Domain

@MainActor
final class CalendarIndexActivityTests: XCTestCase {
    private func activity() -> CalendarIndexActivity {
        CalendarIndexActivity(revealDelay: .milliseconds(80), minimumVisible: .milliseconds(150))
    }

    func testQuickRefreshNeverShowsTheIndicator() async throws {
        let activity = activity()
        activity.update(isIndexing: true, coveredChunks: 0, totalChunks: 0, pacing: .normal)
        try await Task.sleep(for: .milliseconds(20))
        activity.update(isIndexing: false, coveredChunks: 970, totalChunks: 970, pacing: .normal)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(activity.isIndicatorVisible)
    }

    func testLongRefreshRevealsThenStaysAtLeastTheMinimum() async throws {
        let activity = activity()
        activity.update(isIndexing: true, coveredChunks: 10, totalChunks: 100, pacing: .lowPower)
        XCTAssertFalse(activity.isIndicatorVisible, "never instant")
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertTrue(activity.isIndicatorVisible)
        XCTAssertEqual(activity.fraction, 0.1)
        XCTAssertEqual(activity.pacing, .lowPower)

        activity.update(isIndexing: false, coveredChunks: 100, totalChunks: 100, pacing: .lowPower)
        XCTAssertTrue(activity.isIndicatorVisible, "held for the minimum, no blink")
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(activity.isIndicatorVisible)
        XCTAssertEqual(activity.fraction, 1)
    }

    func testRestartingWhileHidingKeepsItVisible() async throws {
        let activity = activity()
        activity.update(isIndexing: true, coveredChunks: 1, totalChunks: 10, pacing: .normal)
        try await Task.sleep(for: .milliseconds(120))
        activity.update(isIndexing: false, coveredChunks: 10, totalChunks: 10, pacing: .normal)
        activity.update(isIndexing: true, coveredChunks: 10, totalChunks: 10, pacing: .normal)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(activity.isIndicatorVisible)
    }
}

extension CalendarIndexActivityTests {
    func testPauseKeepsTheButtonUpAndCallsTheIndex() async throws {
        let activity = activity()
        var requested: [Bool] = []
        activity.onSetPaused = { requested.append($0) }
        activity.update(isIndexing: true, coveredChunks: 10, totalChunks: 100, pacing: .normal)
        try await Task.sleep(for: .milliseconds(120))
        activity.togglePause()
        XCTAssertTrue(activity.isPaused)
        activity.update(isIndexing: false, coveredChunks: 30, totalChunks: 100, pacing: .normal, isPaused: true)
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(activity.showsIndicator, "paused: stays up so it can be resumed")
        activity.togglePause()
        XCTAssertEqual(requested, [true, false])
    }
}
