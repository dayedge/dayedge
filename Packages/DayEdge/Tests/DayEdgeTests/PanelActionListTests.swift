import XCTest
@testable import Domain
@testable import UI

final class PanelActionListTests: XCTestCase {
    private func task(completed: Bool = false, priority: TaskPriority = .none) -> TaskItem {
        TaskItem(id: "t", title: "Śmieci", listID: "home", priority: priority, isCompleted: completed)
    }

    private func taskContext(_ task: TaskItem, readOnly: Bool = false) -> ActionContext {
        ActionContext(mode: .tasks,
                      taskEntries: TaskContextMenuPlan.entries(for: task, isReadOnly: readOnly, context: .tasks))
    }

    private func items(_ entries: [ActionEntry]) -> [ActionItem] {
        entries.compactMap { if case .item(let item) = $0 { item } else { nil } }
    }

    /// The submenu holding `choice`, whatever the language's title.
    private func submenu(containing choice: TaskAction, in entries: [ActionEntry]) -> ActionSubmenu? {
        entries.lazy.compactMap { entry -> ActionSubmenu? in
            guard case .submenu(let menu) = entry, menu.items.contains(where: { $0.row == .task(choice) }) else { return nil }
            return menu
        }.first
    }

    // MARK: Without a selection

    func testWithNothingSelectedOnlyTheAppsCommandsAreListed() {
        let listed = items(PanelActionList.entries(in: ActionContext(mode: .month), matching: ""))
        XCTAssertTrue(listed.allSatisfy { if case .command = $0.row { true } else { false } })
    }

    func testTheViewOnScreenIsNotOfferedAsASwitch() {
        let rows = items(PanelActionList.entries(in: ActionContext(mode: .day), matching: "")).map(\.row)
        XCTAssertFalse(rows.contains(.command(.viewMode(.day))))
    }

    func testAskHasNoToday() {
        let rows = items(PanelActionList.entries(in: ActionContext(mode: .ask), matching: "")).map(\.row)
        XCTAssertFalse(rows.contains(.command(.action(.today))))
    }

    // MARK: A selected task: its menu first, then what can always be done

    func testASelectedTasksMenuComesBeforeTheGeneralCommands() {
        let rows = items(PanelActionList.entries(in: taskContext(task()), matching: "")).map(\.row)
        let lastTask = rows.lastIndex { if case .task = $0 { true } else { false } }
        let firstCommand = rows.firstIndex { if case .command = $0 { true } else { false } }
        XCTAssertNotNil(firstCommand)
        XCTAssertLessThan(lastTask ?? 0, firstCommand ?? 0)
    }

    func testTheTasksViewOffersSorting() {
        let rows = items(PanelActionList.entries(in: taskContext(task()), matching: "")).map(\.row)
        XCTAssertTrue(rows.contains(.command(.action(.openSortMenu))))
    }

    func testSortingIsOnlyOfferedInTasks() {
        let rows = items(PanelActionList.entries(in: ActionContext(mode: .month), matching: "")).map(\.row)
        XCTAssertFalse(rows.contains(.command(.action(.openSortMenu))))
    }

    func testAnOpenTaskOffersCompleting() {
        XCTAssertEqual(items(PanelActionList.entries(in: taskContext(task()), matching: "")).first?.row, .task(.complete))
    }

    func testACompletedTaskOffersReopening() {
        XCTAssertEqual(items(PanelActionList.entries(in: taskContext(task(completed: true)), matching: "")).first?.row,
                       .task(.uncomplete))
    }

    func testThePrioritySubmenuChecksTheCurrentPriority() {
        let menu = submenu(containing: .setPriority(.high),
                           in: PanelActionList.entries(in: taskContext(task(priority: .medium)), matching: ""))
        XCTAssertEqual(menu?.items.filter(\.isChecked).map(\.row), [.task(.setPriority(.medium))])
    }

    func testTheMenusDividersBecomeSeparators() {
        let entries = PanelActionList.entries(in: taskContext(task()), matching: "")
        XCTAssertTrue(entries.contains { if case .separator = $0 { true } else { false } })
    }

    func testDeleteIsDestructive() {
        let delete = items(PanelActionList.entries(in: taskContext(task()), matching: "")).first { $0.row == .task(.delete) }
        XCTAssertEqual(delete?.isDestructive, true)
    }

    func testAReadOnlyTaskCanOnlyBeLookedAtAndCopied() {
        let rows = items(PanelActionList.entries(in: taskContext(task(), readOnly: true), matching: "")).map(\.row)
        XCTAssertFalse(rows.contains(.task(.complete)))
        XCTAssertFalse(rows.contains(.task(.delete)))
        XCTAssertTrue(rows.contains(.task(.copyTitle)))
    }

    func testTypingReachesASubmenusChoice() {
        let found = items(PanelActionList.entries(in: taskContext(task()), matching: TaskPriority.high.title))
        XCTAssertTrue(found.contains { $0.row == .task(.setPriority(.high)) })
    }

    func testTypingDropsSeparators() {
        let entries = PanelActionList.entries(in: taskContext(task()), matching: "a")
        XCTAssertFalse(entries.contains { if case .separator = $0 { true } else { false } })
    }

    // MARK: A selected event

    func testASelectedMeetingListsItsMenuInOrder() {
        let context = ActionContext(mode: .day, eventActions: [.joinVideoCall, .copyMeetingLink, .divider, .deleteEvent])
        let listed = items(PanelActionList.entries(in: context, matching: ""))
        XCTAssertEqual(listed.prefix(3).map(\.row), [.event(.joinVideoCall), .event(.copyMeetingLink), .event(.deleteEvent)])
        XCTAssertEqual(listed.first?.shortcut, .action(.joinSelectedMeeting))
        XCTAssertEqual(listed[2].isDestructive, true)
    }

    // MARK: Tasks views

    func testTasksViewsAreListed() {
        let rows = items(PanelActionList.entries(in: ActionContext(mode: .month), matching: "")).map(\.row)
        XCTAssertTrue(rows.contains(.command(.taskView(.today))))
    }

    func testAListIsOfferedOnlyForAMatchingQuery() {
        let context = ActionContext(mode: .month, taskLists: [CalendarSource(id: "w", title: "Work", tint: .blue)])
        XCTAssertFalse(items(PanelActionList.entries(in: context, matching: "")).contains { $0.row == .taskList("w") })
        XCTAssertTrue(items(PanelActionList.entries(in: context, matching: "work")).contains { $0.row == .taskList("w") })
    }
}
