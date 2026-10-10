import EventKit
import Foundation
import Domain

/// All `EKReminder` I/O, off the main thread. `EKReminder` objects never
/// leave this type: callers get `TaskItem` / `CalendarSource` values back.
/// All on its own serial queue.
package final class EventKitReminderSource: @unchecked Sendable {
    private let eventStore: EKEventStore
    private let queue = DispatchQueue(label: "com.dayedge.eventkitreminders")

    package init(eventStore: EKEventStore) {
        self.eventStore = eventStore
    }

    // MARK: Reading

    package func lists() async -> [CalendarSource] {
        await onQueue { EventKitAccess.calendarSources(eventStore: self.eventStore, entity: .reminder) }
    }

    package func tasks(_ query: TaskQuery, calendar: Calendar) async -> [TaskItem] {
        let lists = await onQueue {
            self.eventStore.calendars(for: .reminder).filter { !query.excludedListIDs.contains($0.calendarIdentifier) }
        }
        guard !lists.isEmpty else { return [] }

        let open = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: lists)
        var items = await fetch(open, calendar: calendar)
        if let since = query.completedSince {
            let done = eventStore.predicateForCompletedReminders(withCompletionDateStarting: since, ending: nil, calendars: lists)
            items += await fetch(done, calendar: calendar)
        }

        // EventKit exposes no manual order; creation order is the stand-in.
        items.sort {
            switch ($0.creationDate, $1.creationDate) {
            case let (a?, b?) where a != b: return a < b
            case (_?, nil): return true
            case (nil, _?): return false
            default: return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        }
        for index in items.indices { items[index].sourceOrder = index }
        return items
    }

    /// The callback runs on an arbitrary thread; mapping happens there so no
    /// `EKReminder` crosses a concurrency boundary.
    private func fetch(_ predicate: NSPredicate, calendar: Calendar) async -> [TaskItem] {
        await withCheckedContinuation { continuation in
            queue.async {
                self.eventStore.fetchReminders(matching: predicate) { reminders in
                    continuation.resume(returning: (reminders ?? []).map { ReminderMapper.taskItem(from: $0, calendar: calendar) })
                }
            }
        }
    }

    // MARK: Writing

    package func apply(_ change: TaskChange, toTaskID id: String, calendar: Calendar) async throws -> TaskItem {
        try await onQueueThrowing {
            let reminder = try self.reminder(withID: id)
            guard reminder.calendar?.allowsContentModifications ?? false else { throw TaskSourceError.readOnlyList }
            try ReminderMapper.write(change, to: reminder, calendar: calendar, eventStore: self.eventStore)
            try self.save(reminder)
            return ReminderMapper.taskItem(from: reminder, calendar: calendar)
        }
    }

    package func delete(taskID id: String) async throws {
        try await onQueueThrowing {
            let reminder = try self.reminder(withID: id)
            guard reminder.calendar?.allowsContentModifications ?? false else { throw TaskSourceError.readOnlyList }
            do {
                try self.eventStore.remove(reminder, commit: true)
            } catch {
                throw TaskSourceError.saveFailed(error.localizedDescription)
            }
        }
    }

    package func create(_ draft: TaskDraft, calendar: Calendar) async throws -> TaskItem {
        try await onQueueThrowing {
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { throw TaskSourceError.saveFailed(L10n.tr("eventkitremindersource.a.reminder.needs.a.title", "A task needs a title.")) }
            let list: EKCalendar
            if let id = draft.listID {
                guard let found = self.eventStore.calendars(for: .reminder).first(where: { $0.calendarIdentifier == id }) else {
                    throw TaskSourceError.notFound
                }
                list = found
            } else if let fallback = self.eventStore.defaultCalendarForNewReminders() {
                list = fallback
            } else {
                throw TaskSourceError.notFound
            }
            guard list.allowsContentModifications else { throw TaskSourceError.readOnlyList }

            let reminder = EKReminder(eventStore: self.eventStore)
            reminder.calendar = list
            ReminderMapper.fill(reminder, from: draft, calendar: calendar)
            try self.save(reminder)
            return ReminderMapper.taskItem(from: reminder, calendar: calendar)
        }
    }

    // MARK: Helpers

    private func reminder(withID id: String) throws -> EKReminder {
        guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
            throw TaskSourceError.notFound
        }
        return reminder
    }

    /// A failed save leaves the edits on the in-memory object; discard them
    /// so the next read shows what is actually stored.
    private func save(_ reminder: EKReminder) throws {
        do {
            try eventStore.save(reminder, commit: true)
        } catch {
            reminder.reset()
            throw TaskSourceError.saveFailed(error.localizedDescription)
        }
    }

    private func onQueueThrowing<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try work() }) }
        }
    }

    private func onQueue<T>(_ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }
}
