import AppKit
import XCTest
@testable import Intelligence

@MainActor
final class ChatTranscriptScrollAnchorsTests: XCTestCase {
    private final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }

    func testRestoresPartiallyVisibleRowAfterInsertionAndTrim() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        let scroll = NSScrollView(frame: root.bounds)
        root.addSubview(scroll)
        let document = FlippedView(frame: NSRect(x: 0, y: 0, width: 300, height: 1_000))
        scroll.documentView = document
        let row = FlippedView(frame: NSRect(x: 0, y: 150, width: 300, height: 50))
        document.addSubview(row)
        let anchors = ChatTranscriptScrollAnchors()
        anchors.attach(row, id: "stable", position: 15)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 170))
        scroll.reflectScrolledClipView(scroll.contentView)
        anchors.observe(offset: 170)
        let saved = anchors.snapshot!
        XCTAssertEqual(saved.id, "stable")
        XCTAssertEqual(saved.offset, -20, accuracy: 0.01)

        row.setFrameOrigin(NSPoint(x: 0, y: 250))
        XCTAssertTrue(anchors.restoreAfterLayout(saved))
        XCTAssertEqual(anchors.capture()!.offset, saved.offset, accuracy: 0.01)
        XCTAssertEqual(scroll.contentView.bounds.minY, 270, accuracy: 0.01)

        row.setFrameOrigin(NSPoint(x: 0, y: 70))
        XCTAssertTrue(anchors.restoreAfterLayout(saved))
        XCTAssertEqual(anchors.capture()!.offset, saved.offset, accuracy: 0.01)
        XCTAssertEqual(scroll.contentView.bounds.minY, 90, accuracy: 0.01)
    }

    func testDismantlingOldProbeDoesNotRemoveItsReplacement() {
        let anchors = ChatTranscriptScrollAnchors()
        let old = NSView(), replacement = NSView()
        anchors.attach(old, id: "row", position: 0)
        anchors.attach(replacement, id: "row", position: 0)
        anchors.detach(old, id: "row")
        XCTAssertEqual(anchors.probeCount, 1)
        anchors.detach(replacement, id: "row")
        XCTAssertEqual(anchors.probeCount, 0)
    }

    func testOngoingUserScrollSupersedesRemainingRestorationPasses() async {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        let scroll = NSScrollView(frame: root.bounds)
        root.addSubview(scroll)
        let document = FlippedView(frame: NSRect(x: 0, y: 0, width: 300, height: 1_000))
        scroll.documentView = document
        let row = FlippedView(frame: NSRect(x: 0, y: 150, width: 300, height: 50))
        document.addSubview(row)
        let anchors = ChatTranscriptScrollAnchors()
        anchors.attach(row, id: "stable", position: 15)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 170))
        anchors.observe(offset: 170)
        let saved = anchors.snapshot!
        // A gesture was already in progress before paging scheduled a restore.
        anchors.userScrolled()
        row.setFrameOrigin(NSPoint(x: 0, y: 250))
        anchors.restore(saved)
        for _ in 0..<10 {
            if scroll.contentView.bounds.minY == 270 { break }
            await nextTurn()
        }
        XCTAssertEqual(scroll.contentView.bounds.minY, 270, accuracy: 0.01)
        // The same hook used by the scoped native wheel/drag monitor; no new
        // SwiftUI scroll-phase transition is needed for this ongoing input.
        anchors.userScrolled()
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 290))
        anchors.observe(offset: 290)
        for _ in 0..<5 { await nextTurn() }
        XCTAssertEqual(scroll.contentView.bounds.minY, 290, accuracy: 0.01)
        XCTAssertEqual(anchors.snapshot?.offset ?? 0, -40, accuracy: 0.01)
        XCTAssertFalse(anchors.isRestoring)
        XCTAssertFalse(anchors.hasInputMonitor)
        withExtendedLifetime(root) {}
    }

    func testInputBeforeFirstDeferredPassCancelsRestoration() async {
        let anchors = ChatTranscriptScrollAnchors()
        let saved = ChatTranscriptScrollAnchors.Snapshot(id: "row", position: 10, offset: -20, visibleIDs: ["row"])
        anchors.restore(saved)
        XCTAssertTrue(anchors.isRestoring)
        anchors.userScrolled()
        for _ in 0..<5 { await nextTurn() }
        XCTAssertFalse(anchors.isRestoring)
        XCTAssertFalse(anchors.hasInputMonitor)
    }

    private func nextTurn() async {
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    }

    func testPhysicalTopDoesNotDependOnWindowStartingAtZero() {
        let anchors = ChatTranscriptScrollAnchors()
        anchors.observe(offset: 100)
        XCTAssertFalse(anchors.isAtTop)
        anchors.observe(offset: 1)
        XCTAssertTrue(anchors.isAtTop)
        anchors.resetToTop()
        XCTAssertNil(anchors.snapshot)
    }
}
