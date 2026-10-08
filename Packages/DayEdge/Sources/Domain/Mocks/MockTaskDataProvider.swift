import Foundation

/// About forty varied reminders, dated relative to `now`, enough to exercise
/// every section, "Show more", and long scrolling.
@MainActor
package final class MockTaskDataProvider: TaskDataProviding {
    private var items: [TaskItem]
    private let listSources: [CalendarSource]
    private var changeContinuation: AsyncStream<Void>.Continuation?
    package let changes: AsyncStream<Void>

    package var accessStatus: SourceAccessStatus
    package let supportsManualOrder = true
    package func openAccessSettings() {}
    /// Test knobs: every write fails with this, and/or takes this long.
    package var failure: TaskSourceError?
    package var latency: Duration = .zero

    package init(now: Date = Date(), calendar: Calendar = .autoupdatingCurrent, accessStatus: SourceAccessStatus = .granted) {
        self.accessStatus = accessStatus
        var continuation: AsyncStream<Void>.Continuation?
        changes = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation = $0 }
        changeContinuation = continuation
        listSources = MockTaskSamples.lists
        items = MockTaskSamples.make(now: now, calendar: calendar)
    }

    package func requestAccess() async -> SourceAccessStatus {
        if accessStatus == .notDetermined { accessStatus = .granted }
        return accessStatus
    }

    package func lists() async -> [CalendarSource] { accessStatus == .granted ? listSources : [] }

    package func tasks(_ query: TaskQuery) async throws -> [TaskItem] {
        guard accessStatus == .granted else { throw TaskSourceError.accessDenied }
        try await simulateWork()
        return items.filter(query.includes)
    }

    package func delete(taskID id: String) async throws {
        try await simulateWork()
        guard items.contains(where: { $0.id == id }) else { throw TaskSourceError.notFound }
        items.removeAll { $0.id == id }
        changeContinuation?.yield()
    }

    package func apply(_ change: TaskChange, toTaskID id: String) async throws -> TaskItem? {
        try await simulateWork()
        guard let index = items.firstIndex(where: { $0.id == id }) else { throw TaskSourceError.notFound }
        items[index] = items[index].applying(change)
        changeContinuation?.yield()
        return items[index]
    }

    package func create(_ draft: TaskDraft) async throws -> TaskItem {
        try await simulateWork()
        let listID = draft.listID ?? listSources[0].id
        let item = TaskItem(
            id: "task-\(items.count + 1)-new", title: draft.title, notes: draft.notes, listID: listID,
            dueDate: draft.dueDate, hasDueTime: draft.hasDueTime, priority: draft.priority,
            recurrence: draft.dueDate == nil ? .never : draft.recurrenceRule?.menuValue ?? .never,
            recurrenceRule: draft.dueDate == nil ? nil : draft.recurrenceRule, alert: draft.alert,
            creationDate: Date(), sourceOrder: (items.map(\.sourceOrder).max() ?? 0) + 1
        )
        items.append(item)
        changeContinuation?.yield()
        return item
    }

    /// Mock tasks aren't in Reminders: nothing to reveal.
    package func revealInSourceApp(taskID id: String) {}

    /// Test hook: as if Reminders changed outside the app.
    package func simulateExternalChange(_ mutate: (inout [TaskItem]) -> Void = { _ in }) {
        mutate(&items)
        changeContinuation?.yield()
    }

    private func simulateWork() async throws {
        if latency > .zero { try await Task.sleep(for: latency) }
        if let failure { throw failure }
    }
}
