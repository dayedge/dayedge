import Foundation

/// What the Tasks side asks a provider for. A struct, not a bare argument
/// list, so the agenda can later add a due-date range without changing the
/// provider contract.
package struct TaskQuery: Equatable, Sendable {
    /// All open tasks are always included; completed ones only when they
    /// were completed at or after this moment (nil leaves them out).
    package var completedSince: Date?
    /// Lists the app ignores everywhere (Settings); never fetched.
    package var excludedListIDs: Set<String> = []

    /// Whether `task` belongs in the answer. Providers that can't filter at
    /// the source use this; it is the single definition of the semantics.
    package func includes(_ task: TaskItem) -> Bool {
        guard !excludedListIDs.contains(task.listID) else { return false }
        guard task.isCompleted else { return true }
        guard let completedSince else { return false }
        // A completed task with no known completion date is kept rather than
        // silently dropped.
        return task.completionDate.map { $0 >= completedSince } ?? true
    }

    package init(completedSince: Date? = nil, excludedListIDs: Set<String> = []) {
        self.completedSince = completedSince
        self.excludedListIDs = excludedListIDs
    }
}

/// A reminder about to be created. Only the fields the quick-add needs.
package struct TaskDraft: Equatable, Sendable {
    package var title: String
    /// nil = the source's own default list.
    package var listID: String?
    package var dueDate: Date?
    package var hasDueTime: Bool = false
    package var priority: TaskPriority = .none
    package var notes: String?
    package var recurrenceRule: TaskRecurrenceRule?
    package var alert: TaskAlert?

    package init(
        title: String,
        listID: String? = nil,
        dueDate: Date? = nil,
        hasDueTime: Bool = false,
        priority: TaskPriority = .none,
        notes: String? = nil,
        recurrenceRule: TaskRecurrenceRule? = nil,
        alert: TaskAlert? = nil
    ) {
        self.title = title
        self.listID = listID
        self.dueDate = dueDate
        self.hasDueTime = hasDueTime
        self.priority = priority
        self.notes = notes
        self.recurrenceRule = recurrenceRule
        self.alert = alert
    }
}
