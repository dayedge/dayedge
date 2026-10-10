import XCTest
@testable import Shell

@MainActor
final class PopoverOutsideClickTests: XCTestCase {
    private let statusButton = CGRect(x: 900, y: 1056, width: 60, height: 24)

    func testAClickOnTheStatusButtonIsInsideEvenOnAForeignWindow() {
        XCTAssertTrue(PopoverWindowController.isInside(clickAt: CGPoint(x: 920, y: 1068), onOwnWindow: false, anchorFrame: statusButton))
    }

    func testAClickElsewhereOnAnotherWindowIsOutside() {
        XCTAssertFalse(PopoverWindowController.isInside(clickAt: CGPoint(x: 200, y: 300), onOwnWindow: false, anchorFrame: statusButton))
    }

    func testAClickOnThePanelItselfIsInside() {
        XCTAssertTrue(PopoverWindowController.isInside(clickAt: CGPoint(x: 200, y: 300), onOwnWindow: true, anchorFrame: statusButton))
    }
}
