import XCTest
@testable import Shell

final class CommandWindowPlacementTests: XCTestCase {
    private let minSize = CGSize(width: 860, height: 560)

    func testCentersHorizontallyOnTheVisibleFrame() {
        let frame = place(CGSize(width: 1000, height: 660), in: CGRect(x: 0, y: 0, width: 1440, height: 875))
        XCTAssertEqual(frame.midX, 720)
    }

    func testSitsAboveTheVerticalMiddle() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let frame = place(CGSize(width: 1000, height: 660), in: visible)
        XCTAssertGreaterThan(frame.midY, visible.midY)
    }

    func testOpensOnTheGivenScreensFrame() {
        let secondScreen = CGRect(x: 1440, y: -200, width: 1920, height: 1055)
        let frame = place(CGSize(width: 1000, height: 660), in: secondScreen)
        XCTAssertTrue(secondScreen.contains(frame))
    }

    func testKeepsTheRememberedSizeWhenItFits() {
        let frame = place(CGSize(width: 1200, height: 700), in: CGRect(x: 0, y: 0, width: 1920, height: 1055))
        XCTAssertEqual(frame.size, CGSize(width: 1200, height: 700))
    }

    func testGrowsASizeBelowTheMinimum() {
        let frame = place(CGSize(width: 400, height: 300), in: CGRect(x: 0, y: 0, width: 1920, height: 1055))
        XCTAssertEqual(frame.size, minSize)
    }

    func testShrinksToAScreenSmallerThanTheMinimum() {
        let visible = CGRect(x: 0, y: 0, width: 800, height: 500)
        let frame = place(CGSize(width: 1000, height: 660), in: visible)
        XCTAssertEqual(frame, visible.insetBy(dx: CommandWindowPlacement.screenMargin, dy: CommandWindowPlacement.screenMargin))
    }

    private func place(_ size: CGSize, in visibleFrame: CGRect) -> CGRect {
        CommandWindowPlacement(size: size, minSize: minSize, visibleFrame: visibleFrame).frame
    }
}
