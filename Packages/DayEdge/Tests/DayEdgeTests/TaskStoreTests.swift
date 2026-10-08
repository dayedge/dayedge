import XCTest
@testable import Shell
@testable import Domain
@testable import UI
@testable import Tasks

@MainActor
final class TaskStoreTests: XCTestCase {
    private func makeStore() async -> TaskStore {
        let defaults = UserDefaults(suiteName: "TaskStoreTests-\(UUID().uuidString)")!
        let store = TaskStore(provider: MockTaskDataProvider(), defaults: defaults)
        await store.load()
        return store
    }

    func testLoadsListsAndTasks() async {
        let store = await makeStore()
        XCTAssertEqual(store.lists.count, 4)
        XCTAssertGreaterThan(store.tasks.count, 90)
        XCTAssertNotNil(store.headerSubtitle(query: ""))
    }

    func testOverviewStaysBoundedUntilASectionIsExpanded() async {
        let store = await makeStore()
        let work = store.sections(query: "").first { $0.kind == .list("work") }
        XCTAssertEqual(work?.tasks.count, 5)
        XCTAssertGreaterThan(work?.hiddenCount ?? 0, 50)
        XCTAssertLessThan(store.sections(query: "").flatMap(\.tasks).count, 40)

        store.toggleExpanded("list-work")
        XCTAssertGreaterThan(store.sections(query: "").first { $0.kind == .list("work") }?.tasks.count ?? 0, 60)
        XCTAssertEqual(store.sections(query: "").first { $0.kind == .list("personal") }?.tasks.count, 5) // still folded
        store.toggleExpanded("list-work")
        XCTAssertEqual(store.sections(query: "").first { $0.kind == .list("work") }?.tasks.count, 5)
    }

    func testChipJumpSetsActiveSectionWithoutTouchingSelection() async {
        let store = await makeStore()
        store.select("task-1")
        store.jump(to: "list-personal")
        XCTAssertEqual(store.currentSectionID(), "list-personal")
        XCTAssertEqual(store.jumpRequest?.sectionID, "list-personal")
        XCTAssertEqual(store.selectedTaskID, "task-1")
    }

    func testArrowSectionNavigationJumpsBetweenLandmarks() async throws {
        let store = await makeStore()
        let order = store.navigableSections().map(\.id)
        XCTAssertEqual(order.first, "attention")
        XCTAssertEqual(store.currentSectionID(), "attention") // default: the first landmark

        store.moveSection(1, query: "")
        XCTAssertEqual(store.currentSectionID(), order[1])
        let firstTask = try XCTUnwrap(store.navigableSections()[1].tasks.first)
        XCTAssertEqual(store.selectedTaskID, firstTask.id) // predictable landing
        XCTAssertEqual(store.jumpRequest?.sectionID, order[1])

        store.moveSection(-1, query: "")
        XCTAssertEqual(store.currentSectionID(), "attention")
        store.moveSection(-1, query: "")
        XCTAssertEqual(store.currentSectionID(), "attention") // clamped at the ends
        for _ in 0..<20 { store.moveSection(1, query: "") }
        XCTAssertEqual(store.currentSectionID(), order.last)
    }

    func testSectionJumpIgnoresHowManyTasksASectionHas() async {
        let store = await makeStore()
        store.toggleExpanded("list-work") // 60+ rows expanded
        let order = store.navigableSections().map(\.id)
        let work = order.firstIndex(of: "list-work")!
        store.jump(to: "list-work")
        store.moveSection(1, query: "")
        XCTAssertEqual(store.currentSectionID(), order[work + 1]) // one press, not 60
    }

    func testMovingThroughTasksCarriesTheActiveSection() async {
        let store = await makeStore()
        let attentionCount = store.navigableSections().first!.tasks.count
        for _ in 0...attentionCount { store.moveSelection(.down, query: "") } // one past the last attention task
        XCTAssertNotEqual(store.currentSectionID(), "attention")
    }

    func testCompletedIsTheLastLandmarkAndNavigatingIntoItDoesNotExpandIt() async {
        let store = await makeStore()
        let order = store.navigableSections().map(\.id)
        XCTAssertEqual(order.last, "completed")
        store.jump(to: order[order.count - 2])
        store.moveSection(1, query: "")
        XCTAssertEqual(store.currentSectionID(), "completed")
        XCTAssertNil(store.selectedTaskID)
        XCTAssertFalse(store.completedExpanded) // navigation has no large side effect
        XCTAssertEqual(store.sections(query: "").last?.tasks.count, 0)
    }

    func testReturnAndSpaceOnCompletedToggleItAndBatchesGrow() async {
        let store = await makeStore()
        store.jump(to: "completed")
        store.toggleDetailForSelection() // Return
        XCTAssertTrue(store.completedExpanded)
        XCTAssertEqual(store.sections(query: "").last?.tasks.count, 15) // first batch only
        store.showMoreCompleted()
        XCTAssertEqual(store.sections(query: "").last?.tasks.count, 30)
        store.completeSelected() // Space with nothing selected folds it again
        XCTAssertFalse(store.completedExpanded)
        store.toggleCompletedExpanded()
        XCTAssertEqual(store.sections(query: "").last?.tasks.count, 15) // paging was forgotten
    }

    // MARK: Visibility (selector)

    func testHidingAListRemovesItsSectionChipAndAttentionTasks() async throws {
        let store = await makeStore()
        XCTAssertTrue(store.navigableSections().map(\.id).contains("list-work"))
        let attentionWork = store.sections(query: "").first { $0.kind == .needsAttention }?.tasks.filter { $0.listID == "work" }.count ?? 0
        XCTAssertGreaterThan(attentionWork, 0)

        store.toggleVisibility("work")
        let ids = store.navigableSections().map(\.id)
        XCTAssertFalse(ids.contains("list-work")) // section and chip gone together
        XCTAssertEqual(TaskNavigatorItem.items(from: store.sections(query: "")).map(\.id), ids)
        XCTAssertFalse(store.sections(query: "").flatMap(\.tasks).contains { $0.listID == "work" }) // even in Attention
        XCTAssertEqual(ids.first, "attention") // order of the rest is preserved
    }

    func testHidingAttentionSendsItsTasksBackToTheirLists() async {
        let store = await makeStore()
        store.toggleVisibility(TaskSmartSection.attention.visibilityID)
        XCTAssertNil(store.sections(query: "").first { $0.kind == .needsAttention })
        XCTAssertNil(store.navigableSections().first { $0.id == "attention" })
        let personal = store.sections(query: "").first { $0.kind == .list("personal") }
        XCTAssertTrue(personal?.tasks.contains { $0.title == "Call the bank" } ?? false) // due today: now in its list
    }

    func testHidingCompletedDropsThatSection() async {
        let store = await makeStore()
        XCTAssertNotNil(store.sections(query: "").first { $0.kind == .completed })
        store.toggleVisibility(TaskSmartSection.completed.visibilityID)
        XCTAssertNil(store.sections(query: "").first { $0.kind == .completed })
    }

    func testActiveSectionFallsBackWhenItsListIsHidden() async {
        let store = await makeStore()
        store.jump(to: "list-work")
        store.toggleVisibility("work")
        XCTAssertNotEqual(store.currentSectionID(), "list-work")
        XCTAssertNotNil(store.currentSectionID())
    }

    func testSearchOnlyCoversVisibleLists() async {
        let store = await makeStore()
        XCTAssertEqual(store.sections(query: "milk").flatMap(\.tasks).count, 1)
        store.toggleVisibility("groceries")
        XCTAssertTrue(store.sections(query: "milk").isEmpty)
    }

    func testSoloAndShowAllForLists() async {
        let store = await makeStore()
        store.solo("home")
        XCTAssertEqual(store.listVisibility.summaryLabel, "Home")
        store.listVisibility.showAll()
        XCTAssertEqual(store.listVisibility.summaryLabel, "All Lists")
        store.solo(TaskSmartSection.attention.visibilityID) // smart sections don't solo
        XCTAssertTrue(store.listVisibility.isEverythingVisible)
    }

    func testSelectorGroupsAreBySourceThenSmart() async {
        let store = await makeStore()
        let groups = store.selectorGroups
        XCTAssertEqual(groups.map(\.title), ["Exchange", "iCloud Reminders", "Smart"])
        XCTAssertEqual(groups.first { $0.title == "Exchange" }?.items.map(\.title), ["Groceries"])
        XCTAssertEqual(groups.last?.items.map(\.title), ["Attention", "Completed"])
    }

    func testSortChangeKeepsSelectionAndSectionAndPersists() async throws {
        let defaults = UserDefaults(suiteName: "TaskStoreTests-\(UUID().uuidString)")!
        let store = TaskStore(provider: MockTaskDataProvider(), defaults: defaults)
        await store.load()
        XCTAssertEqual(store.sortMode, .smart) // default for new users
        store.jump(to: "list-personal")
        let personal = try XCTUnwrap(store.sections(query: "").first { $0.kind == .list("personal") })
        let selected = try XCTUnwrap(personal.tasks.last?.id)
        store.select(selected)

        store.setSort(.title, direction: .descending)
        XCTAssertEqual(store.selectedTaskID, selected)
        XCTAssertEqual(store.currentSectionID(), "list-personal")
        let titles = store.sections(query: "").first { $0.kind == .list("personal") }?.tasks.map(\.title) ?? []
        XCTAssertEqual(titles, titles.sorted { $0.localizedStandardCompare($1) == .orderedDescending })

        let reloaded = TaskStore(provider: MockTaskDataProvider(), defaults: defaults)
        XCTAssertEqual(reloaded.sortMode, .title)
        XCTAssertEqual(reloaded.sortDirection, .descending)
        XCTAssertEqual(reloaded.sortAccessibilityValue, "Title, Z to A")
    }

    func testScrollspyUpdatesActiveSectionOnly() async {
        let store = await makeStore()
        store.select("task-1")
        store.setActiveSectionFromScroll("list-home")
        XCTAssertEqual(store.currentSectionID(), "list-home")
        XCTAssertEqual(store.selectedTaskID, "task-1")
        XCTAssertNil(store.jumpRequest) // never scrolls the view itself
    }

    func testSearchIsAcrossAllLists() async {
        let store = await makeStore()
        store.jump(to: "list-work")
        let hits = store.sections(query: "milk").flatMap(\.tasks)
        XCTAssertEqual(hits.map(\.title), ["Milk"]) // a Groceries task, found from inside Work
        XCTAssertEqual(store.sections(query: "September hours").flatMap(\.tasks).count, 1) // notes
        XCTAssertTrue(store.sections(query: "zzzzz").isEmpty)
        XCTAssertEqual(store.headerSubtitle(query: "milk"), "1 result")
    }

    func testCompletionLingersThenMoves() async throws {
        let store = await makeStore()
        let target = try XCTUnwrap(store.tasks.first { !$0.isCompleted && $0.title == "Call the bank" })
        store.toggleCompleted(target.id)
        // Immediately: checked, but still in Needs attention.
        let attention = store.sections(query: "").first { $0.kind == .needsAttention }
        XCTAssertEqual(attention?.tasks.first { $0.id == target.id }?.isCompleted, true)
        try await Task.sleep(for: .milliseconds(1900))
        XCTAssertNil(store.sections(query: "").first { $0.kind == .needsAttention }?.tasks.first { $0.id == target.id })
        // Undo flips it back.
        store.toggleCompleted(target.id)
        XCTAssertEqual(store.tasks.first { $0.id == target.id }?.isCompleted, false)
    }

    func testKeyboardSelectionWalksVisibleRowsAndClamps() async {
        let store = await makeStore()
        let ordered = store.sections(query: "").flatMap { $0.tasks.map(\.id) }
        XCTAssertLessThan(ordered.count, 40) // keyboard walks only the bounded rows
        store.moveSelection(.down, query: "")
        XCTAssertEqual(store.selectedTaskID, ordered[0])
        store.moveSelection(.down, query: "")
        XCTAssertEqual(store.selectedTaskID, ordered[1])
        store.moveSelection(.up, query: "")
        store.moveSelection(.up, query: "")
        XCTAssertEqual(store.selectedTaskID, ordered[0]) // clamped at the top
        XCTAssertNotNil(store.scrollRequest)
    }

    func testDetailToggleAndDismiss() async {
        let store = await makeStore()
        store.select("task-1")
        store.toggleDetailForSelection()
        XCTAssertEqual(store.presentedDetailID, "task-1")
        XCTAssertTrue(store.dismissDetail())
        XCTAssertFalse(store.dismissDetail())
    }

    func testCompletingFromDetailsClosesItAndAnnounces() async throws {
        let defaults = UserDefaults(suiteName: "TaskStoreTests-\(UUID().uuidString)")!
        let notices = NoticeCenter()
        let store = TaskStore(provider: MockTaskDataProvider(), noticeCenter: notices, defaults: defaults)
        await store.load()
        let task = try XCTUnwrap(store.tasks.first { $0.title == "Call the bank" })
        store.select(task.id)
        store.toggleDetail(for: task.id)
        store.toggleCompleted(task.id, closingDetail: true)
        XCTAssertNil(store.presentedDetailID)
        XCTAssertEqual(notices.currentNotice?.title, "Task completed")
        XCTAssertEqual(notices.currentNotice?.action?.title, "Undo")
    }

    func testDeletingJustHappensWithUndo() async throws {
        let defaults = UserDefaults(suiteName: "TaskStoreTests-\(UUID().uuidString)")!
        let notices = NoticeCenter()
        let store = TaskStore(provider: MockTaskDataProvider(), noticeCenter: notices, defaults: defaults)
        await store.load()
        let task = try XCTUnwrap(store.tasks.first { $0.title == "Milk" })
        store.perform(.delete, on: task)
        XCTAssertFalse(store.tasks.contains { $0.id == task.id }, "no confirmation: it's reversible")
        XCTAssertEqual(notices.currentNotice?.title, "Task deleted")

        notices.performAction(for: try XCTUnwrap(notices.currentNotice).id)
        try await Task.sleep(for: .milliseconds(50))
        await store.repository.flush()
        XCTAssertTrue(store.tasks.contains { $0.title == "Milk" }, "Undo puts it back")
    }

    func testEditReachesTheModelAndTheProvider() async throws {
        let store = await makeStore()
        let task = try XCTUnwrap(store.tasks.first { $0.title == "Clean up old branches" })
        let before = store.revision
        store.edit(.title("Prune branches"), taskID: task.id)
        store.edit(.notes("Keep main"), taskID: task.id)
        XCTAssertEqual(store.tasks.first { $0.id == task.id }?.title, "Prune branches")
        XCTAssertEqual(store.tasks.first { $0.id == task.id }?.notes, "Keep main")
        XCTAssertGreaterThan(store.revision, before)
        // The provider saw it too.
        await store.repository.flush()
        await store.repository.reload()
        XCTAssertEqual(store.tasks.first { $0.id == task.id }?.title, "Prune branches")
    }

    func testAnExactRepeatRuleIsWrittenAndClearedWithTheDueDate() async throws {
        let store = await makeStore()
        let task = try XCTUnwrap(store.tasks.first { $0.dueDate != nil && !$0.isRecurring })
        let rule = TaskRecurrenceRule(frequency: .weekly, interval: 2, weekdays: [.init(weekday: 2), .init(weekday: 4)])
        store.edit(.recurrenceRule(rule), taskID: task.id)
        XCTAssertEqual(store.tasks.first { $0.id == task.id }?.recurrenceRule, rule)
        XCTAssertEqual(store.tasks.first { $0.id == task.id }?.isRecurring, true)
        await store.repository.flush()
        await store.repository.reload()
        XCTAssertEqual(store.tasks.first { $0.id == task.id }?.recurrenceRule, rule, "the provider kept it")

        store.edit(.recurrenceRule(nil), taskID: task.id)
        XCTAssertNil(store.tasks.first { $0.id == task.id }?.recurrenceRule)
        XCTAssertEqual(store.tasks.first { $0.id == task.id }?.recurrence, .never)
    }

    func testEditingWhileDetailsAreOpenKeepsTheRowInPlaceUntilClose() async throws {
        let store = await makeStore()
        let task = try XCTUnwrap(store.tasks.first { $0.title == "Clean up old branches" }) // an undated Work task
        store.toggleExpanded("list-work") // so the row is on screen regardless of rank
        store.toggleDetail(for: task.id)
        store.edit(.due(Date().addingTimeInterval(-86_400 * 3), hasTime: false), taskID: task.id) // now overdue
        let whileOpen = store.sections(query: "")
        XCTAssertFalse(whileOpen.first { $0.kind == .needsAttention }?.tasks.contains { $0.id == task.id } ?? false)
        let stillInWork = whileOpen.first { $0.kind == .list("work") }?.tasks.first { $0.id == task.id }
        XCTAssertNotNil(stillInWork) // held in place...
        XCTAssertNotNil(stillInWork?.dueDate) // ...but showing live data
        store.dismissDetail()
        let settled = store.sections(query: "").first { $0.kind == .needsAttention }
        XCTAssertTrue(settled?.tasks.contains { $0.id == task.id } ?? false) // moved on close
    }

    func testMovingToAnotherListSettlesOnClose() async throws {
        let store = await makeStore()
        let task = try XCTUnwrap(store.tasks.first { $0.title == "Milk" })
        store.toggleDetail(for: task.id)
        store.edit(.list("home"), taskID: task.id)
        XCTAssertEqual(store.tasks.first { $0.id == task.id }?.listID, "home")
        store.dismissDetail()
        let home = store.sections(query: "").first { $0.kind == .list("home") }
        let attention = store.sections(query: "").first { $0.kind == .needsAttention }
        let landedInHome = home?.tasks.contains { $0.id == task.id } ?? false
        let landedInAttention = attention?.tasks.contains { $0.id == task.id } ?? false
        XCTAssertTrue(landedInHome || landedInAttention)
    }

    func testPriorityAndDueChanges() async throws {
        let store = await makeStore()
        let task = try XCTUnwrap(store.tasks.first { $0.title == "Clean up old branches" })
        store.perform(.setPriority(.high), on: task)
        XCTAssertEqual(store.tasks.first { $0.id == task.id }?.priority, .high)
        store.perform(.setDue(.tomorrow), on: task)
        XCTAssertNotNil(store.tasks.first { $0.id == task.id }?.dueDate)
        store.perform(.setDue(.none), on: task)
        XCTAssertNil(store.tasks.first { $0.id == task.id }?.dueDate)
    }
}

@MainActor
final class TaskStoreRevealTests: XCTestCase {
    private func makeStore() async -> TaskStore {
        let defaults = UserDefaults(suiteName: "TaskStoreRevealTests-\(UUID().uuidString)")!
        let store = TaskStore(provider: MockTaskDataProvider(), defaults: defaults)
        await store.load()
        return store
    }

    func testRevealExpandsTheTasksSectionSelectsAndScrollsToIt() async throws {
        let store = await makeStore()
        // Deep in the long Work backlog: folded away in the overview.
        let task = try XCTUnwrap(store.tasks.first { $0.title == "Backlog item 50" })
        XCTAssertFalse(store.sections(query: "").flatMap(\.tasks).contains { $0.id == task.id })

        XCTAssertTrue(store.reveal(task.id))
        XCTAssertTrue(store.sections(query: "").first { $0.id == "list-work" }?.tasks.contains { $0.id == task.id } ?? false)
        XCTAssertEqual(store.selectedTaskID, task.id)
        XCTAssertEqual(store.currentSectionID(), "list-work", "the navigator chip follows")
        XCTAssertEqual(store.scrollRequest?.taskID, task.id)
    }

    func testRevealUsesTheSectionTasksKeepsItIn() async throws {
        let store = await makeStore()
        let urgent = try XCTUnwrap(store.tasks.first { $0.title == "Send invoice to client" }) // overdue, high
        XCTAssertTrue(store.reveal(urgent.id))
        XCTAssertEqual(store.currentSectionID(), "attention")
    }

    func testRevealShowsAListHiddenByTheFooterFilter() async throws {
        let store = await makeStore()
        let milk = try XCTUnwrap(store.tasks.first { $0.title == "Olive oil" })
        store.toggleVisibility("groceries")
        XCTAssertFalse(store.listVisibility.isVisible("groceries"))
        XCTAssertTrue(store.reveal(milk.id))
        XCTAssertTrue(store.listVisibility.isVisible("groceries"))
        XCTAssertEqual(store.selectedTaskID, milk.id)
    }

    func testRevealFindsACompletedTaskInCompleted() async throws {
        let store = await makeStore()
        let done = try XCTUnwrap(store.tasks.first { $0.title == "Done: chore 40" })
        XCTAssertTrue(store.reveal(done.id))
        XCTAssertEqual(store.currentSectionID(), "completed")
        XCTAssertTrue(store.sections(query: "").first { $0.id == "completed" }?.tasks.contains { $0.id == done.id } ?? false)
    }

    func testRevealingAnUnknownTaskFailsHonestly() async {
        let store = await makeStore()
        XCTAssertFalse(store.reveal("nope"))
        XCTAssertNil(store.selectedTaskID)
    }

    func testCalendarMenuOffersShowInTasksAndOpenInReminders() {
        let task = TaskItem(id: "1", title: "A", listID: "l", dueDate: Date())
        let entries = TaskContextMenuPlan.entries(for: task, context: .calendar)
        let showIndex = entries.firstIndex(of: .action(.showInTasks))
        XCTAssertNotNil(showIndex)
        XCTAssertEqual(entries[showIndex! + 1], .action(.showInReminders))
        XCTAssertEqual(TaskContextMenuPlan.title(for: .showInTasks), "Show in Tasks")
        XCTAssertFalse(TaskContextMenuPlan.entries(for: task).contains(.action(.showInTasks)), "not in the Tasks view itself")
    }
}
