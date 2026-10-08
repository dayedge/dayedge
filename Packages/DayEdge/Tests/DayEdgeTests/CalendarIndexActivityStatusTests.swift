import XCTest
@testable import Shell
@testable import Domain

@MainActor
final class CalendarIndexActivityStatusTests: XCTestCase {
    private func activity() -> CalendarIndexActivity { CalendarIndexActivity(revealDelay: .zero, minimumVisible: .zero) }

    func testStatusFollowsTheIndex() {
        let activity = activity()
        XCTAssertEqual(activity.status, .upToDate)
        activity.update(isIndexing: true, coveredChunks: 3, totalChunks: 10, pacing: .normal)
        XCTAssertEqual(activity.status, .indexing)
        activity.update(isIndexing: true, coveredChunks: 3, totalChunks: 10, pacing: .normal, isPaused: true)
        XCTAssertEqual(activity.status, .paused)
        activity.update(hasAccess: false)
        XCTAssertEqual(activity.status, .noAccess, "no access outranks paused")
        activity.isUnavailable = true
        XCTAssertEqual(activity.status, .unavailable)
    }

    func testTemporaryIndexIsFlaggedOnceIdle() {
        let activity = activity()
        activity.isTemporary = true
        XCTAssertEqual(activity.status, .temporary)
    }

    func testReindexRunsOnceUntilNearMonthsAreBack() {
        let activity = activity()
        var calls = 0
        activity.onReindex = { calls += 1 }
        activity.update(isIndexing: true, coveredChunks: 9, totalChunks: 10, pacing: .normal, isPaused: true)
        activity.reindex()
        activity.reindex()
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(activity.isReindexing)
        activity.didReset()
        XCTAssertFalse(activity.isPaused, "reindexing resumes")
        XCTAssertNil(activity.fraction, "progress starts over")
        XCTAssertEqual(activity.status, .indexing)
        activity.nearReady()
        XCTAssertFalse(activity.isReindexing)
    }
}
