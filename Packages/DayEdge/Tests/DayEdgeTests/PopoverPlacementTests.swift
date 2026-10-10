import XCTest
@testable import Shell

final class PopoverPlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let size = CGSize(width: 420, height: 709)

    func testCentersWhenThereIsRoom() {
        let placement = place(x: 720)
        XCTAssertEqual(placement.windowOrigin.x, 510)
        XCTAssertEqual(placement.arrowX, 210)
    }

    func testShiftsLeftAtTheRightEdgeAndKeepsTheArrowOnTheIcon() {
        let placement = place(x: 1380)
        XCTAssertEqual(placement.windowOrigin.x, 1020)
        XCTAssertEqual(placement.windowOrigin.x + placement.arrowX, 1380)
    }

    func testShiftsRightAtTheLeftEdgeAndKeepsTheArrowOnTheIcon() {
        let placement = place(x: 60)
        XCTAssertEqual(placement.windowOrigin.x, 0)
        XCTAssertEqual(placement.windowOrigin.x + placement.arrowX, 60)
    }

    func testAnExactlyFittingCenteredWindowDoesNotShift() {
        let placement = place(x: 1230)
        XCTAssertEqual(placement.windowOrigin.x, 1020)
        XCTAssertEqual(placement.arrowX, 210)
    }

    func testRightCornerClearanceTakesPriorityAtTheExtremeEdge() {
        let placement = place(x: 1430)
        XCTAssertEqual(placement.windowOrigin.x, 1020)
        XCTAssertEqual(placement.arrowX, 386)
    }

    func testLeftCornerClearanceTakesPriorityAtTheExtremeEdge() {
        let placement = place(x: 10)
        XCTAssertEqual(placement.windowOrigin.x, 0)
        XCTAssertEqual(placement.arrowX, 34)
    }

    func testUsesTheSuppliedVisibleFrameIncludingASideDock() {
        let visible = CGRect(x: 0, y: 0, width: 1360, height: 900)
        let placement = place(x: 1300, in: visible)
        XCTAssertEqual(placement.windowOrigin.x, 940)
        XCTAssertEqual(placement.windowOrigin.x + placement.arrowX, 1300)
    }

    func testUsesNegativeDisplayCoordinates() {
        let visible = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let placement = place(x: -60, in: visible)
        XCTAssertEqual(placement.windowOrigin.x, -420)
        XCTAssertEqual(placement.windowOrigin.x + placement.arrowX, -60)
    }

    func testUsesPositiveDisplayCoordinates() {
        let visible = CGRect(x: 1440, y: 400, width: 1920, height: 1080)
        let placement = place(x: 3300, in: visible)
        XCTAssertEqual(placement.windowOrigin.x, 2940)
        XCTAssertEqual(placement.windowOrigin.x + placement.arrowX, 3300)
    }

    func testPreservesTheVerticalAnchorGap() {
        let placement = place(x: 720)
        XCTAssertEqual(placement.windowOrigin.y + size.height, 899)
    }

    private func place(x: CGFloat, in visibleFrame: CGRect? = nil) -> PopoverPlacement {
        PopoverPlacement(
            anchor: PopoverAnchor(point: CGPoint(x: x, y: 900), visibleFrame: visibleFrame ?? screen),
            windowSize: size,
            arrowInset: 34
        )
    }
}
