import AppKit
import XCTest
@testable import Shell
@testable import Domain
@testable import UI

final class TaskContextMenuPlanTests: XCTestCase {
    func testFirstEntryFollowsCompletionState() {
        let open = TaskItem(id: "1", title: "A", listID: "l")
        var done = open
        done.isCompleted = true
        XCTAssertEqual(TaskContextMenuPlan.entries(for: open).first, .action(.complete))
        XCTAssertEqual(TaskContextMenuPlan.entries(for: done).first, .action(.uncomplete))
    }

    func testMenuOffersPriorityDueAndRemindersHandoff() {
        let entries = TaskContextMenuPlan.entries(for: TaskItem(id: "1", title: "A", listID: "l"))
        XCTAssertTrue(entries.contains(.action(.showInReminders)))
        XCTAssertEqual(entries.last, .action(.delete))
        XCTAssertEqual(TaskContextMenuPlan.title(for: .delete), "Delete Task…")
        XCTAssertEqual(TaskContextMenuPlan.title(for: .showInReminders), "Open in Reminders")
        XCTAssertTrue(entries.contains(.action(.copyTitle)))
        let titles = entries.compactMap { entry -> String? in
            if case .submenu(let title, _, _, _) = entry { return title } else { return nil }
        }
        XCTAssertEqual(titles, ["Priority", "Due Date"])
        XCTAssertEqual(TaskContextMenuPlan.title(for: .uncomplete), "Mark as Incomplete")
    }

    func testGroupsMatchTheEventMenu() {
        var task = TaskItem(id: "1", title: "A", listID: "l", dueDate: Date(), hasDueTime: false)
        task.priority = .high
        let entries = TaskContextMenuPlan.entries(for: task)
        XCTAssertEqual(entries.map(Self.describe), [
            "complete", "|", "Priority", "Due Date", "|", "showInCalendar", "showInReminders", "copyTitle", "|", "delete"
        ])
        guard case .submenu(_, "flag", _, let checked) = entries[2] else { return XCTFail("priority submenu") }
        XCTAssertEqual(checked, .setPriority(.high), "the current priority is checked")
        guard case .submenu(_, "calendar.badge.clock", _, nil) = entries[3] else { return XCTFail("due submenu, never checked") }

        task.recurrence = .daily
        XCTAssertEqual(TaskContextMenuPlan.entries(for: task, context: .calendar).map(Self.describe), [
            "complete", "|", "Priority", "Due Date", "|", "showInTasks", "showInReminders", "copyTitle", "|",
            "nextOccurrence", "previousOccurrence", "|", "delete"
        ])
        XCTAssertEqual(TaskContextMenuPlan.entries(for: task, isReadOnly: true, context: .calendar).map(Self.describe), [
            "showInTasks", "showInReminders", "copyTitle", "|", "nextOccurrence", "previousOccurrence"
        ])
        XCTAssertEqual(TaskContextMenuPlan.entries(for: task, isReadOnly: true).map(Self.describe),
                       ["showInCalendar", "showInReminders", "copyTitle"])
    }

    func testEveryActionHasASystemSymbol() {
        let actions: [TaskAction] = [.complete, .uncomplete, .showInReminders, .showInCalendar, .showInTasks,
                                     .nextOccurrence, .previousOccurrence, .copyTitle, .delete]
        for action in actions {
            let symbol = try? XCTUnwrap(action.symbolName)
            XCTAssertNotNil(symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }, "\(action)")
        }
        for symbol in ["flag", "calendar.badge.clock"] {
            XCTAssertNotNil(NSImage(systemSymbolName: symbol, accessibilityDescription: nil), symbol)
        }
        XCTAssertNil(TaskAction.setPriority(.high).symbolName, "submenu choices are text only")
    }

    private static func describe(_ entry: TaskMenuEntry) -> String {
        switch entry {
        case .divider: return "|"
        case .submenu(let title, _, _, _): return title
        case .action(let action): return String(describing: action)
        }
    }

    func testDuePresetsResolveRelativeToNow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 15))!
        let today = calendar.startOfDay(for: now)
        XCTAssertEqual(TaskDuePreset.today.date(from: now, calendar: calendar), today)
        XCTAssertEqual(TaskDuePreset.tomorrow.date(from: now, calendar: calendar), calendar.date(byAdding: .day, value: 1, to: today))
        XCTAssertEqual(TaskDuePreset.nextWeek.date(from: now, calendar: calendar), calendar.date(byAdding: .day, value: 7, to: today))
        XCTAssertNil(TaskDuePreset.none.date(from: now, calendar: calendar))
    }
}
