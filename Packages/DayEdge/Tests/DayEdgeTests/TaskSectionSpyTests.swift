import XCTest
@testable import Shell
@testable import Tasks

final class TaskSectionSpyTests: XCTestCase {
    private let order = ["attention", "list-w", "list-p", "list-g"]
    private let line: CGFloat = 60

    private func active(_ offsets: [String: CGFloat], current: String?) -> String? {
        TaskSectionSpy.activeSection(headerOffsets: offsets, order: order, current: current, activationLine: line)
    }

    func testLastReachedHeaderIsActive() {
        XCTAssertEqual(active(["attention": -300, "list-w": 40, "list-p": 500], current: nil), "list-w")
    }

    func testTopOfDocumentBeforeAnyHeaderReachedIsFirstVisible() {
        XCTAssertEqual(active(["attention": 80, "list-w": 400], current: nil), "attention")
    }

    func testForwardSwitchNeedsToCrossTheLineByTheHysteresis() {
        // Personal's header just touches the line: not yet.
        XCTAssertEqual(active(["list-w": 20, "list-p": 55], current: "list-w"), "list-w")
        // Clearly past it: switch.
        XCTAssertEqual(active(["list-w": 20, "list-p": 40], current: "list-w"), "list-p")
    }

    func testBackwardSwitchNeedsTheCurrentHeaderClearlyBelowTheLine() {
        XCTAssertEqual(active(["list-w": 20, "list-p": 65], current: "list-p"), "list-p")
        XCTAssertEqual(active(["list-w": 20, "list-p": 90], current: "list-p"), "list-w")
    }

    func testNoFlickerWhenABoundarySitsOnTheLine() {
        var current: String? = "list-w"
        for offset in stride(from: 70, through: 50, by: -1) { // Personal creeping over the line
            current = active(["list-w": 0, "list-p": CGFloat(offset)], current: current)
        }
        XCTAssertEqual(current, "list-w")
        for offset in stride(from: 50, through: 70, by: 1) { // and back again
            current = active(["list-w": 0, "list-p": CGFloat(offset)], current: current)
        }
        XCTAssertEqual(current, "list-w")
    }

    func testUnknownCurrentFallsBackToCandidateAndEmptyKeepsCurrent() {
        XCTAssertEqual(active(["list-g": 10], current: "list-w"), "list-g") // current header not rendered
        XCTAssertEqual(active([:], current: "list-p"), "list-p")
        XCTAssertEqual(active([:], current: nil), "attention")
    }
}
