import SwiftUI
import XCTest
@testable import Shell
@testable import Domain
@testable import UI
@testable import Tasks

final class TaskNavigatorItemTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return c
    }()
    private lazy var now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 12))!
    private let lists = [
        CalendarSource(id: "w", title: "Work", tint: .blue),
        CalendarSource(id: "p", title: "Personal", tint: .green),
        CalendarSource(id: "e", title: "Empty", tint: .red)
    ]

    private func sections(_ tasks: [TaskItem]) -> [TaskSection] {
        TaskBuckets.sections(tasks: tasks, lists: lists, now: now, calendar: calendar)
    }

    private func item(_ id: String, list: String = "w", due: Int? = nil, done: Bool = false) -> TaskItem {
        TaskItem(
            id: id, title: id, listID: list,
            dueDate: due.map { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: now))! },
            isCompleted: done, completionDate: done ? now : nil
        )
    }

    func testChipCountsAreTheSectionTotalsNotThePreview() {
        let work = (0..<12).map { item("w\($0)", due: 3 + $0) }
        let attention = (0..<8).map { item("a\($0)", due: -1) }
        let done = (0..<20).map { item("d\($0)", done: true) }
        let all = sections(work + attention + done)
        let chips = TaskNavigatorItem.items(from: all)

        XCTAssertEqual(chips.map(\.id), ["attention", "list-w", "completed"])
        XCTAssertEqual(chips.map(\.count), [8, 12, 20]) // totals; previews show 6 / 5 / 0
        // One source of truth: the chip equals its section header's count.
        for chip in chips {
            XCTAssertEqual(chip.count, all.first { $0.id == chip.id }?.totalCount)
        }
    }

    func testEmptySectionsGetNoChip() {
        let chips = TaskNavigatorItem.items(from: sections([item("w1", due: 5)]))
        XCTAssertEqual(chips.map(\.id), ["list-w"]) // no Attention, no Completed, no empty list
    }

    func testSymbolsAndAttentionFlags() {
        let chips = TaskNavigatorItem.items(from: sections([
            item("a", due: -1), item("w1", due: 5), item("d", done: true)
        ]))
        XCTAssertTrue(chips[0].isAttention)
        XCTAssertNil(chips[1].symbol)
        XCTAssertEqual(chips[2].symbol, "checkmark")
    }

    func testAccessibilityLabelReadsAsWordsWithPlurals() {
        let chips = TaskNavigatorItem.items(from: sections([item("w1", due: 5), item("p1", list: "p", due: 5), item("p2", list: "p", due: 6)]))
        XCTAssertEqual(chips[0].accessibilityLabel, "Work, 1 task")
        XCTAssertEqual(chips[1].accessibilityLabel, "Personal, 2 tasks")
    }
}
