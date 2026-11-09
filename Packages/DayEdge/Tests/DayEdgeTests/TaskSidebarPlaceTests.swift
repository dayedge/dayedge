import XCTest
@testable import Domain
@testable import UI
@testable import Tasks

final class TaskSidebarPlaceTests: XCTestCase {
    private func place(_ filter: TaskFilter = .today, inView: String? = "list-w") -> TaskSidebarPlace {
        TaskSidebarPlace(filter: filter, sectionInView: inView, counts: ["attention": 2, "list-w": 5])
    }

    func testTheFilterStaysSelectedWhileAListIsInView() {
        XCTAssertTrue(place().isSelected(.today))
        XCTAssertFalse(place().isSelected(.all))
    }

    func testTheListInViewIsMarkedUnderANarrowFilter() {
        XCTAssertTrue(place().isInView("list-w"))
        XCTAssertFalse(place().isInView("attention"))
    }

    func testASectionTheFilterLeavesEmptyIsUnavailableWithNoTasks() {
        XCTAssertFalse(place().contains("list-p"))
        XCTAssertEqual(place().count("list-p"), 0)
    }

    func testASectionCountsWhatTheFilterLeavesInIt() {
        XCTAssertTrue(place().contains("list-w"))
        XCTAssertEqual(place().count("list-w"), 5)
    }
}
