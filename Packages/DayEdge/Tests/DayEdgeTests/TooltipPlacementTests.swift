import SwiftUI
import XCTest
@testable import Shell
@testable import UI

final class TooltipPlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let size = CGSize(width: 100, height: 30)

    func testAboveTheAnchorWithAGapAndCentered() {
        let anchor = CGRect(x: 600, y: 400, width: 40, height: 20)
        let result = TooltipPlacement.frame(for: size, anchor: anchor, edge: .top, screen: screen)
        XCTAssertEqual(result.edge, .top)
        XCTAssertEqual(result.frame.minY, anchor.maxY + TooltipPlacement.gap) // AppKit y grows upward
        XCTAssertEqual(result.frame.midX, anchor.midX)
    }

    func testBelowTheAnchor() {
        let anchor = CGRect(x: 600, y: 400, width: 40, height: 20)
        let result = TooltipPlacement.frame(for: size, anchor: anchor, edge: .bottom, screen: screen)
        XCTAssertEqual(result.edge, .bottom)
        XCTAssertEqual(result.frame.maxY, anchor.minY - TooltipPlacement.gap)
    }

    func testFlipsWhenThePreferredEdgeHasNoRoom() {
        let nearTop = CGRect(x: 600, y: 880, width: 40, height: 16)
        XCTAssertEqual(TooltipPlacement.frame(for: size, anchor: nearTop, edge: .top, screen: screen).edge, .bottom)
        let nearBottom = CGRect(x: 600, y: 4, width: 40, height: 16)
        XCTAssertEqual(TooltipPlacement.frame(for: size, anchor: nearBottom, edge: .bottom, screen: screen).edge, .top)
    }

    func testClampsInsideTheScreenHorizontally() {
        let left = TooltipPlacement.frame(for: size, anchor: CGRect(x: 0, y: 400, width: 10, height: 10), edge: .top, screen: screen)
        XCTAssertEqual(left.frame.minX, TooltipPlacement.screenMargin)
        let right = TooltipPlacement.frame(for: size, anchor: CGRect(x: 1435, y: 400, width: 5, height: 10), edge: .top, screen: screen)
        XCTAssertEqual(right.frame.maxX, screen.maxX - TooltipPlacement.screenMargin)
    }
}
