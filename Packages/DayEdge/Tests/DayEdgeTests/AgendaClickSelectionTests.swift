import XCTest
@testable import Domain
@testable import UI
@testable import Agenda

/// A click selects its row: the agenda has one selection, whether the
/// mouse or the keyboard made it.
@MainActor
final class AgendaClickSelectionTests: XCTestCase {
    private let day = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 26))!

    private func coordinator() -> AgendaScrollCoordinator {
        AgendaScrollCoordinator(store: AgendaSectionStore(dataProvider: MockCalendarDataProvider(), calendar: .autoupdatingCurrent),
                                scrollTarget: nil)
    }

    func testAClickedTaskBecomesTheKeyboardSelection() {
        let scroll = coordinator()
        let anchor = AgendaScrollAnchor.task(sectionID: day, taskID: "milk")
        var reported: AgendaSelection?
        scroll.selectClicked(anchor) { reported = $0 }
        XCTAssertEqual(scroll.keyboardAnchor, anchor)
        guard case .task(let selection)? = reported else { return XCTFail("no task selection reported") }
        XCTAssertEqual(selection.taskID, "milk")
    }

    func testClickingTheSelectedRowAgainReportsNothing() {
        let scroll = coordinator()
        let anchor = AgendaScrollAnchor.task(sectionID: day, taskID: "milk")
        scroll.selectClicked(anchor) { _ in }
        var reports = 0
        scroll.selectClicked(anchor) { _ in reports += 1 }
        XCTAssertEqual(reports, 0)
    }
}
