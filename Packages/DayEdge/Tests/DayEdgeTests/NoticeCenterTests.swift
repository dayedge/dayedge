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

    func testAutoDismissAndRepeatedNoticeResetsTimer() async throws {
        let center = NoticeCenter()
        center.show(TransientNotice(style: .information, title: "Short", duration: 0.08))
        try await Task.sleep(nanoseconds: 50_000_000)
        center.show(TransientNotice(style: .information, title: "Short", duration: 0.08))
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNotNil(center.currentNotice)
        try await Task.sleep(nanoseconds: 55_000_000)
        XCTAssertNil(center.currentNotice)
    }

    func testHoverPausesActionableNoticeAndActionRunsOnce() async throws {
        let center = NoticeCenter()
        var activations = 0
        center.show(TransientNotice(
            style: .success, title: "Removed",
            action: NoticeAction(title: "Undo", handler: { activations += 1 }),
            duration: 0.07
        ))
        let id = try XCTUnwrap(center.currentNotice?.id)
        center.setHovering(true, for: id)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNotNil(center.currentNotice)
        center.performAction(for: id)
        center.performAction(for: id)
        XCTAssertEqual(activations, 1)
        XCTAssertNil(center.currentNotice)
    }

    func testHoverResumesRemainingTime() async throws {
        let center = NoticeCenter()
        center.show(TransientNotice(
            style: .success, title: "Saved",
            action: NoticeAction(title: "Undo", handler: {}), duration: 0.08
        ))
        let id = try XCTUnwrap(center.currentNotice?.id)
        try await Task.sleep(nanoseconds: 30_000_000)
        center.setHovering(true, for: id)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNotNil(center.currentNotice)
        center.setHovering(false, for: id)
        try await Task.sleep(nanoseconds: 65_000_000)
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
