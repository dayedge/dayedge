import XCTest
@testable import Shell
@testable import Domain

@MainActor
final class CalendarIndexActivityTests: XCTestCase {
    private func activity(clock: ActivityTestClock) -> CalendarIndexActivity {
        CalendarIndexActivity(revealDelay: .milliseconds(80), minimumVisible: .milliseconds(150), now: clock.now, schedule: clock.schedule)
    }

    func testQuickRefreshNeverShowsTheIndicator() {
        let clock = ActivityTestClock()
        let activity = activity(clock: clock)
        activity.update(isIndexing: true, coveredChunks: 0, totalChunks: 0, pacing: .normal)
        clock.advance(by: .milliseconds(20))
        activity.update(isIndexing: false, coveredChunks: 970, totalChunks: 970, pacing: .normal)
        clock.advance(by: .milliseconds(150))
        XCTAssertFalse(activity.isIndicatorVisible)
    }

    func testLongRefreshRevealsThenStaysAtLeastTheMinimum() {
        let clock = ActivityTestClock()
        let activity = activity(clock: clock)
        activity.update(isIndexing: true, coveredChunks: 10, totalChunks: 100, pacing: .lowPower)
        XCTAssertFalse(activity.isIndicatorVisible, "never instant")
        clock.advance(by: .milliseconds(120))
        XCTAssertTrue(activity.isIndicatorVisible)
        XCTAssertEqual(activity.fraction, 0.1)
        XCTAssertEqual(activity.pacing, .lowPower)

        activity.update(isIndexing: false, coveredChunks: 100, totalChunks: 100, pacing: .lowPower)
        XCTAssertTrue(activity.isIndicatorVisible, "held for the minimum, no blink")
        clock.advance(by: .milliseconds(140))
        XCTAssertTrue(activity.isIndicatorVisible)
        clock.advance(by: .milliseconds(10))
        XCTAssertFalse(activity.isIndicatorVisible)
        XCTAssertEqual(activity.fraction, 1)
    }

    func testRestartingWhileHidingKeepsItVisible() {
        let clock = ActivityTestClock()
        let activity = activity(clock: clock)
        activity.update(isIndexing: true, coveredChunks: 1, totalChunks: 10, pacing: .normal)
        clock.advance(by: .milliseconds(120))
        activity.update(isIndexing: false, coveredChunks: 10, totalChunks: 10, pacing: .normal)
        activity.update(isIndexing: true, coveredChunks: 10, totalChunks: 10, pacing: .normal)
        clock.advance(by: .milliseconds(250))
        XCTAssertTrue(activity.isIndicatorVisible)
    }
}

extension CalendarIndexActivityTests {
    func testPauseKeepsTheButtonUpAndCallsTheIndex() {
        let clock = ActivityTestClock()
        let activity = activity(clock: clock)
        var requested: [Bool] = []
        activity.onSetPaused = { requested.append($0) }
        activity.update(isIndexing: true, coveredChunks: 10, totalChunks: 100, pacing: .normal)
        clock.advance(by: .milliseconds(120))
        activity.togglePause()
        XCTAssertTrue(activity.isPaused)
        activity.update(isIndexing: false, coveredChunks: 30, totalChunks: 100, pacing: .normal, isPaused: true)
        clock.advance(by: .milliseconds(250))
        XCTAssertTrue(activity.showsIndicator, "paused: stays up so it can be resumed")
        activity.togglePause()
        XCTAssertEqual(requested, [true, false])
    }
}

@MainActor
private final class ActivityTestClock {
    private var current = ContinuousClock.now
    private var pending: [UUID: (deadline: ContinuousClock.Instant, action: @MainActor () -> Void)] = [:]

    func now() -> ContinuousClock.Instant { current }

    func schedule(after delay: Duration, action: @escaping @MainActor () -> Void) -> (@MainActor () -> Void) {
        let id = UUID()
        pending[id] = (current.advanced(by: delay), action)
        return { [weak self] in self?.pending[id] = nil }
    }

    func advance(by interval: Duration) {
        current = current.advanced(by: interval)
        let due = pending.filter { $0.value.deadline <= current }
        for (id, entry) in due {
            pending[id] = nil
            entry.action()
        }
    }
}
