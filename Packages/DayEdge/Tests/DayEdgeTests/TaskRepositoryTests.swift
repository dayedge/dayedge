import XCTest
@testable import Shell
@testable import Domain
@testable import UI

@MainActor
final class TaskRepositoryTests: XCTestCase {
    private func makeRepository(
        provider: MockTaskDataProvider? = nil,
        notices: NoticeCenter? = nil
    ) async -> (TaskRepository, MockTaskDataProvider) {
        let defaults = UserDefaults(suiteName: "TaskRepositoryTests-\(UUID().uuidString)")!
        let provider = provider ?? MockTaskDataProvider()
        let repository = TaskRepository(
            provider: provider,
            listVisibility: SourceVisibilityStore(kind: .taskLists, defaults: defaults),
            noticeCenter: notices, defaults: defaults
        )
        await repository.reload()
        return (repository, provider)
    }

    private func task(titled title: String, in repository: TaskRepository) throws -> TaskItem {
        try XCTUnwrap(repository.tasks.first { $0.title == title })
    }

    func testLoadFillsListsTasksAndVisibilityCatalogue() async {
        let (repository, _) = await makeRepository()
        XCTAssertEqual(repository.lists.count, 4)
        XCTAssertGreaterThan(repository.tasks.count, 90)
        XCTAssertEqual(repository.listVisibility.allItems.count, 4)
        XCTAssertEqual(repository.accessStatus, .granted)
    }

    func testWithoutAccessNothingLoadsAndRequestingGrantsIt() async {
        let (repository, _) = await makeRepository(provider: MockTaskDataProvider(accessStatus: .notDetermined))
        XCTAssertTrue(repository.tasks.isEmpty)
        XCTAssertEqual(repository.accessStatus, .notDetermined)

        await repository.requestAccess()
        XCTAssertEqual(repository.accessStatus, .granted)
        XCTAssertFalse(repository.tasks.isEmpty)
    }

    func testDeniedAccessStaysEmpty() async {
        let (repository, _) = await makeRepository(provider: MockTaskDataProvider(accessStatus: .denied))
        XCTAssertTrue(repository.tasks.isEmpty)
        XCTAssertEqual(repository.accessStatus, .denied)
    }

    func testEditShowsImmediatelyThenSettlesOnTheStoredResult() async throws {
        let (repository, provider) = await makeRepository()
        let target = try task(titled: "Clean up old branches", in: repository)
        repository.apply(.title("Prune branches"), toTaskID: target.id)
        XCTAssertEqual(repository.tasks.first { $0.id == target.id }?.title, "Prune branches") // before any await

        await repository.flush()
        XCTAssertEqual(repository.tasks.first { $0.id == target.id }?.title, "Prune branches")
        let stored = try await provider.tasks(TaskQuery(completedSince: .distantPast))
        XCTAssertEqual(stored.first { $0.id == target.id }?.title, "Prune branches")
    }

    func testFailedWriteRollsBackAndTellsTheUser() async throws {
        let notices = NoticeCenter()
        let (repository, provider) = await makeRepository(notices: notices)
        provider.failure = .saveFailed("Disk full")
        let target = try task(titled: "Clean up old branches", in: repository)

        repository.apply(.title("Prune branches"), toTaskID: target.id)
        XCTAssertEqual(repository.tasks.first { $0.id == target.id }?.title, "Prune branches")
        await repository.flush()

        XCTAssertEqual(repository.tasks.first { $0.id == target.id }?.title, "Clean up old branches")
        XCTAssertEqual(notices.currentNotice?.title, "Couldn't update reminder")
        XCTAssertEqual(notices.currentNotice?.message, "Disk full")
        XCTAssertEqual(repository.lastError, .saveFailed("Disk full"))
    }

    func testWaitingWritesReportTheOutcomeInsteadOfANotice() async throws {
        let notices = NoticeCenter()
        let (repository, provider) = await makeRepository(notices: notices)
        let target = try task(titled: "Clean up old branches", in: repository)

        try await repository.applyAndWait(.title("Prune branches"), toTaskID: target.id)
        let stored = try await provider.tasks(TaskQuery(completedSince: .distantPast))
        XCTAssertEqual(stored.first { $0.id == target.id }?.title, "Prune branches", "saved by the time it returns")

        provider.failure = .saveFailed("Disk full")
        do {
            try await repository.applyAndWait(.title("Other"), toTaskID: target.id)
            XCTFail("expected the failure")
        } catch {
            XCTAssertEqual(error as? TaskSourceError, .saveFailed("Disk full"))
        }
        XCTAssertEqual(repository.tasks.first { $0.id == target.id }?.title, "Prune branches", "rolled back")
        XCTAssertNil(notices.currentNotice, "the caller says it, not a global notice")

        do {
            try await repository.deleteAndWait(taskID: target.id)
            XCTFail("expected the failure")
        } catch {}
        XCTAssertNotNil(repository.tasks.first { $0.id == target.id }, "still there")
    }

    func testFailedEditDoesNotTakeAnEarlierPendingEditWithIt() async throws {
        let (repository, provider) = await makeRepository()
        provider.latency = .milliseconds(20)
        let target = try task(titled: "Clean up old branches", in: repository)

        repository.apply(.notes("Keep main"), toTaskID: target.id)
        provider.failure = nil
        repository.apply(.priority(.high), toTaskID: target.id)
        await repository.flush()

        let result = try XCTUnwrap(repository.tasks.first { $0.id == target.id })
        XCTAssertEqual(result.notes, "Keep main")
        XCTAssertEqual(result.priority, .high)
    }

    func testReloadDuringAPendingWriteKeepsTheOptimisticValue() async throws {
        let (repository, provider) = await makeRepository()
        provider.latency = .milliseconds(80)
        let target = try task(titled: "Clean up old branches", in: repository)

        repository.apply(.title("Prune branches"), toTaskID: target.id)
        await repository.reload() // fetches while the write is still in flight
        XCTAssertEqual(repository.tasks.first { $0.id == target.id }?.title, "Prune branches")
        await repository.flush()
        XCTAssertEqual(repository.tasks.first { $0.id == target.id }?.title, "Prune branches")
    }

    func testDeleteIsOptimisticAndRollsBackOnFailure() async throws {
        let (repository, provider) = await makeRepository()
        let target = try task(titled: "Milk", in: repository)
        repository.delete(taskID: target.id)
        XCTAssertFalse(repository.tasks.contains { $0.id == target.id })
        await repository.flush()
        XCTAssertFalse(repository.tasks.contains { $0.id == target.id })

        let other = try task(titled: "Eggs", in: repository)
        provider.failure = .readOnlyList
        repository.delete(taskID: other.id)
        await repository.flush()
        XCTAssertTrue(repository.tasks.contains { $0.id == other.id })
    }

    func testExternalChangeTriggersAReload() async throws {
        let (repository, provider) = await makeRepository()
        repository.start()
        defer { repository.stop() }
        let before = repository.tasks.count

        provider.simulateExternalChange { $0.removeAll { $0.title == "Milk" } }
        for _ in 0..<50 where repository.tasks.count == before { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(repository.tasks.count, before - 1)
    }

    func testExcludingAListReloadsButHidingOneDoesNot() async throws {
        let (repository, _) = await makeRepository()
        repository.start()
        defer { repository.stop() }
        XCTAssertTrue(repository.tasks.contains { $0.listID == "groceries" })

        repository.listVisibility.setEnabled(false, id: "groceries")
        for _ in 0..<50 where repository.tasks.contains(where: { $0.listID == "groceries" }) {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(repository.tasks.contains { $0.listID == "groceries" })
        XCTAssertEqual(repository.lists.count, 4) // Settings still offers it

        let revision = repository.revision
        repository.listVisibility.toggle("work") // footer filter: a view concern only
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(repository.revision, revision)
    }

    func testCompletedWindowLimitsWhichCompletedTasksLoad() async throws {
        let provider = MockTaskDataProvider()
        let defaults = UserDefaults(suiteName: "TaskRepositoryTests-\(UUID().uuidString)")!
        defaults.set(7, forKey: TaskSettings.completedWindowKey)
        let repository = TaskRepository(
            provider: provider, listVisibility: SourceVisibilityStore(kind: .taskLists, defaults: defaults), defaults: defaults
        )
        await repository.reload()
        let completedNarrow = repository.tasks.filter(\.isCompleted).count

        defaults.set(90, forKey: TaskSettings.completedWindowKey)
        await repository.reloadIfCompletedWindowChanged()
        XCTAssertGreaterThan(repository.tasks.filter(\.isCompleted).count, completedNarrow)
    }

    func testQueryIncludesRules() {
        let now = Date()
        let open = TaskItem(id: "1", title: "a", listID: "l")
        let recentlyDone = TaskItem(id: "2", title: "b", listID: "l", isCompleted: true, completionDate: now)
        let longDone = TaskItem(id: "3", title: "c", listID: "l", isCompleted: true, completionDate: now.addingTimeInterval(-86_400 * 60))
        let undated = TaskItem(id: "4", title: "d", listID: "l", isCompleted: true)
        let query = TaskQuery(completedSince: now.addingTimeInterval(-86_400 * 30))
        XCTAssertTrue(query.includes(open))
        XCTAssertTrue(query.includes(recentlyDone))
        XCTAssertFalse(query.includes(longDone))
        XCTAssertTrue(query.includes(undated))
        XCTAssertFalse(TaskQuery(completedSince: nil).includes(recentlyDone))
        XCTAssertFalse(TaskQuery(completedSince: nil, excludedListIDs: ["l"]).includes(open))
    }
}

@MainActor
final class TaskQuickAddCreationTests: XCTestCase {
    func testCreateAddsTheReminderAndUndoRemovesIt() async throws {
        let defaults = UserDefaults(suiteName: "TaskQuickAddCreationTests-\(UUID().uuidString)")!
        let notices = NoticeCenter()
        let repository = TaskRepository(
            provider: MockTaskDataProvider(),
            listVisibility: SourceVisibilityStore(kind: .taskLists, defaults: defaults),
            noticeCenter: notices, defaults: defaults
        )
        await repository.reload()
        let actions = TaskActions(repository: repository)
        let due = Calendar.current.startOfDay(for: Date())
        let rule = TaskRecurrenceRule(frequency: .weekly)

        let item = try await actions.create(TaskDraft(title: "Send invoice", listID: "work", dueDate: due, priority: .high, recurrenceRule: rule))
        let created = try XCTUnwrap(repository.tasks.first { $0.id == item.id }, "shown at once, before any reload")
        XCTAssertEqual(created.title, "Send invoice")
        XCTAssertEqual(created.listID, "work")
        XCTAssertEqual(created.priority, .high)
        XCTAssertEqual(created.recurrenceRule, rule)
        XCTAssertEqual(notices.currentNotice?.title, "Task created")

        notices.currentNotice?.action?.handler()
        await repository.flush()
        XCTAssertFalse(repository.tasks.contains { $0.id == created.id }, "Undo deletes it again")
    }
}
