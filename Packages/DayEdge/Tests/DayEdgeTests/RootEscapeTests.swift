import XCTest
@testable import Shell

final class RootEscapeTests: XCTestCase {
    func testAQueryIsClearedFirstInThePopover() {
        XCTAssertEqual(RootEscape(queryIsEmpty: false, closesWindow: false), .clearQuery)
    }

    func testAQueryIsClearedFirstInTheCommandWindow() {
        XCTAssertEqual(RootEscape(queryIsEmpty: false, closesWindow: true), .clearQuery)
    }

    func testThePopoverLeavesTheFieldWithAnEmptyQuery() {
        XCTAssertEqual(RootEscape(queryIsEmpty: true, closesWindow: false), .leaveField)
    }

    func testTheCommandWindowClosesWithAnEmptyQuery() {
        XCTAssertEqual(RootEscape(queryIsEmpty: true, closesWindow: true), .closeWindow)
    }
}
