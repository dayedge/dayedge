import XCTest
@testable import Domain
@testable import Agenda

final class MonthChipLayoutTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_790_000_000)

    private func timed(_ id: String, minutes: Int) -> AgendaEventModel {
        AgendaEventModel(id: id, startTime: "x", endTime: "y", startDate: base.addingTimeInterval(Double(minutes) * 60), title: id)
    }

    private func allDay(_ id: String) -> AgendaEventModel {
        AgendaEventModel(id: id, title: id)
    }

    func testShowsEveryEventWhenTheyFit() {
        let layout = MonthChipLayout(events: [timed("a", minutes: 0), timed("b", minutes: 60)], rows: 2)
        XCTAssertEqual(layout.visible.map(\.id), ["a", "b"])
        XCTAssertEqual(layout.overflowCount, 0)
    }

    func testTheLastRowBecomesOverflowWhenTheyDoNotFit() {
        let events = (0..<5).map { timed("e\($0)", minutes: $0 * 60) }
        let layout = MonthChipLayout(events: events, rows: 3)
        XCTAssertEqual(layout.visible.map(\.id), ["e0", "e1"])
        XCTAssertEqual(layout.overflowCount, 3)
    }

    func testAllDayEventsComeFirst() {
        let layout = MonthChipLayout(events: [timed("t", minutes: 0), allDay("d")], rows: 2)
        XCTAssertEqual(layout.visible.map(\.id), ["d", "t"])
    }

    func testTimedEventsAreOrderedByStart() {
        let layout = MonthChipLayout(events: [timed("late", minutes: 120), timed("early", minutes: 30)], rows: 2)
        XCTAssertEqual(layout.visible.map(\.id), ["early", "late"])
    }

    func testACellWithoutRoomShowsOnlyTheCount() {
        let layout = MonthChipLayout(events: [timed("a", minutes: 0), timed("b", minutes: 60)], rows: 0)
        XCTAssertTrue(layout.visible.isEmpty)
        XCTAssertEqual(layout.overflowCount, 2)
    }

    func testRowCountFollowsTheCellHeight() {
        let header: CGFloat = 22
        let oneRow = header + MonthChipLayout.chipHeight
        XCTAssertEqual(MonthChipLayout.rowCount(cellHeight: oneRow, headerHeight: header), 1)
        XCTAssertEqual(MonthChipLayout.rowCount(cellHeight: oneRow + MonthChipLayout.chipSpacing + MonthChipLayout.chipHeight,
                                                headerHeight: header), 2)
        XCTAssertEqual(MonthChipLayout.rowCount(cellHeight: header - 5, headerHeight: header), 0)
    }
}
