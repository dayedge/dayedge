import EventKit
import Foundation
import Domain

/// Reminders through EventKit, behind `TaskDataProviding`. Shares the app's
/// one `EKEventStore` with the calendar side; only the entity type differs.
@MainActor
package final class EventKitTaskProvider: TaskDataProviding {
    private let eventStore: EKEventStore
    private let source: EventKitReminderSource
    private let calendar: Calendar
    private var continuation: AsyncStream<Void>.Continuation?
    private var storeObserver: NSObjectProtocol?
    private var debounce: Task<Void, Never>?
    package let changes: AsyncStream<Void>

    /// EventKit has no manual reminder order to show.
    package let supportsManualOrder = false

    package var accessStatus: SourceAccessStatus { EventKitAccess.status(for: .reminder) }
    package func openAccessSettings() { EventKitAccess.openPrivacySettings(for: .reminder) }

    package init(eventStore: EKEventStore, calendar: Calendar = .autoupdatingCurrent) {
        self.eventStore = eventStore
        self.calendar = calendar
        source = EventKitReminderSource(eventStore: eventStore)
        var continuation: AsyncStream<Void>.Continuation?
        changes = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation = $0 }
        self.continuation = continuation

        // EKEventStoreChanged can't be told apart by entity, and fires for
        // our own saves too; coalesce the bursts. The repository's reload is
        // cheap and idempotent.
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: eventStore, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleChange() }
        }
    }

    private func scheduleChange() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.continuation?.yield()
        }
    }

    package func requestAccess() async -> SourceAccessStatus {
        if EKEventStore.authorizationStatus(for: .reminder) == .notDetermined {
            _ = try? await eventStore.requestFullAccessToReminders()
        }
        return accessStatus
    }

    package func lists() async -> [CalendarSource] {
        guard accessStatus == .granted else { return [] }
        return await source.lists()
    }

    package func tasks(_ query: TaskQuery) async throws -> [TaskItem] {
        guard accessStatus == .granted else { throw TaskSourceError.accessDenied }
        return await source.tasks(query, calendar: calendar)
    }

    package func apply(_ change: TaskChange, toTaskID id: String) async throws -> TaskItem? {
        guard accessStatus == .granted else { throw TaskSourceError.accessDenied }
        return try await source.apply(change, toTaskID: id, calendar: calendar)
    }

    package func delete(taskID id: String) async throws {
        guard accessStatus == .granted else { throw TaskSourceError.accessDenied }
        try await source.delete(taskID: id)
    }

    package func create(_ draft: TaskDraft) async throws -> TaskItem {
        guard accessStatus == .granted else { throw TaskSourceError.accessDenied }
        return try await source.create(draft, calendar: calendar)
    }

    package func revealInSourceApp(taskID id: String) { RemindersBridge.open() }
}
