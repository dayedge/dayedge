import XCTest
@testable import Shell
@testable import Domain

@MainActor
final class NoticeCenterTests: XCTestCase {
    func testNoticeContentAndAccessibility() {
        let oneLine = TransientNotice.information(title: "No previous occurrence found")
        XCTAssertEqual(oneLine.style, .information)
        XCTAssertNil(oneLine.message)
        XCTAssertNil(oneLine.action)
        XCTAssertEqual(oneLine.duration, 3)
        XCTAssertEqual(oneLine.accessibilityAnnouncement, "No previous occurrence found")

        let twoLine = TransientNotice.information(
            title: "No previous occurrence", message: "None found within 4 years."
        )
        XCTAssertEqual(twoLine.accessibilityAnnouncement, "No previous occurrence. None found within 4 years.")

        let undo = TransientNotice.success(
            title: "Cancelled event removed", action: NoticeAction(title: "Undo", handler: {})
        )
        XCTAssertEqual(undo.duration, 5.5)
        XCTAssertEqual(undo.accessibilityAnnouncement, "Cancelled event removed. Undo available.")
        XCTAssertEqual(TransientNotice.error(title: "Couldn’t open meeting link").duration, 4.5)
    }

    func testReplacementAndRepeatedNotice() {
        let center = NoticeCenter()
        center.show(.information(title: "First"))
        let firstID = center.currentNotice?.id

        center.show(.information(title: "First"))
        XCTAssertEqual(center.currentNotice?.id, firstID)

        center.show(.error(title: "Second"))
        XCTAssertEqual(center.currentNotice?.title, "Second")
        XCTAssertNotEqual(center.currentNotice?.id, firstID)
    }

    func testAutoDismissAndRepeatedNoticeResetsTimer() {
        let clock = NoticeTestClock()
        let center = NoticeCenter(now: clock.now, schedule: clock.schedule)
        center.show(TransientNotice(style: .information, title: "Short", duration: 8))
        clock.advance(by: 5)
        center.show(TransientNotice(style: .information, title: "Short", duration: 8))
        clock.advance(by: 5)
        XCTAssertNotNil(center.currentNotice)
        clock.advance(by: 3)
        XCTAssertNil(center.currentNotice)
    }

    func testHoverPausesActionableNoticeAndActionRunsOnce() throws {
        let clock = NoticeTestClock()
        let center = NoticeCenter(now: clock.now, schedule: clock.schedule)
        var activations = 0
        center.show(TransientNotice(
            style: .success, title: "Removed",
            action: NoticeAction(title: "Undo", handler: { activations += 1 }),
            duration: 7
        ))
        let id = try XCTUnwrap(center.currentNotice?.id)
        center.setHovering(true, for: id)
        clock.advance(by: 10)
        XCTAssertNotNil(center.currentNotice)
        center.performAction(for: id)
        center.performAction(for: id)
        XCTAssertEqual(activations, 1)
        XCTAssertNil(center.currentNotice)
    }

    func testHoverResumesRemainingTime() throws {
        let clock = NoticeTestClock()
        let center = NoticeCenter(now: clock.now, schedule: clock.schedule)
        center.show(TransientNotice(
            style: .success, title: "Saved",
            action: NoticeAction(title: "Undo", handler: {}), duration: 8
        ))
        let id = try XCTUnwrap(center.currentNotice?.id)
        clock.advance(by: 3)
        center.setHovering(true, for: id)
        clock.advance(by: 10)
        XCTAssertNotNil(center.currentNotice)
        center.setHovering(false, for: id)
        clock.advance(by: 4)
        XCTAssertNotNil(center.currentNotice)
        clock.advance(by: 1)
        XCTAssertNil(center.currentNotice)
    }

    func testEscapeDismissesOnlyPassiveNotice() {
        let center = NoticeCenter()
        center.show(.information(title: "No next occurrence found"))
        center.dismissIfPassive()
        XCTAssertNil(center.currentNotice)

        center.show(.success(title: "Removed", action: NoticeAction(title: "Undo", handler: {})))
        center.dismissIfPassive()
        XCTAssertNotNil(center.currentNotice)
    }
}

@MainActor
private final class NoticeTestClock {
    private var current = Date(timeIntervalSince1970: 0)
    private var pending: [UUID: (deadline: Date, action: @MainActor () -> Void)] = [:]

    func now() -> Date { current }

    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) -> (@MainActor () -> Void) {
        let id = UUID()
        pending[id] = (current.addingTimeInterval(delay), action)
        return { [weak self] in self?.pending[id] = nil }
    }

    func advance(by interval: TimeInterval) {
        current = current.addingTimeInterval(interval)
        let due = pending.filter { $0.value.deadline <= current }
        for (id, entry) in due {
            pending[id] = nil
            entry.action()
        }
    }
}
