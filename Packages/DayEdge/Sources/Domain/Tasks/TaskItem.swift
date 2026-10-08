import Foundation

package enum TaskPriority: Int, Codable, CaseIterable, Sendable {
    case none = 0
    case low
    case medium
    case high

    /// Stable assistant vocabulary; never derived from a translated title.
    package var assistantValue: String {
        switch self {
        case .none: return "none"
        case .low: return "low"
        case .medium: return "medium"
        case .high: return "high"
        }
    }

    package var title: String {
        switch self {
        case .none: return L10n.tr("taskitem.none", "None")
        case .low: return L10n.tr("taskitem.low", "Low")
        case .medium: return L10n.tr("taskitem.medium", "Medium")
        case .high: return L10n.tr("taskitem.high", "High")
        }
    }
}

/// A reminder as the Tasks view sees it. Storage-agnostic: the mock
/// provider and (later) the EventKit Reminders provider both produce these.
package struct TaskItem: Identifiable, Hashable, Sendable {
    package let id: String
    package var title: String
    package var notes: String?
    package var url: URL?
    package var listID: String
    package var dueDate: Date?
    /// False for date-only reminders ("due Sep 28", no clock time).
    package var hasDueTime: Bool
    package var priority: TaskPriority
    package var isCompleted: Bool
    package var completionDate: Date?
    package var recurrence: TaskRecurrence
    /// The exact rule behind `recurrence`, when the source has one — what
    /// later occurrences are computed from. nil falls back to the rule the
    /// menu value stands for.
    package var recurrenceRule: TaskRecurrenceRule?
    package var alert: TaskAlert?
    /// nil when the source doesn't know it; never invented.
    package var creationDate: Date?
    /// When the source last saw a change; nil when it doesn't say.
    package var lastModifiedDate: Date?
    /// Position in the source's own order (Reminders order); the stable
    /// tie-breaker for every sort.
    package var sourceOrder: Int

    package var isRecurring: Bool { recurrence.isRepeating }

    /// The rule to compute later occurrences with; nil when not repeating
    /// or not computable.
    package var effectiveRecurrenceRule: TaskRecurrenceRule? {
        guard isRecurring else { return nil }
        return recurrenceRule ?? TaskRecurrenceRule(standard: recurrence)
    }

    package init(id: String, title: String, notes: String? = nil, url: URL? = nil, listID: String,
                 dueDate: Date? = nil, hasDueTime: Bool = false, priority: TaskPriority = .none,
                 isCompleted: Bool = false, completionDate: Date? = nil,
                 recurrence: TaskRecurrence = .never, recurrenceRule: TaskRecurrenceRule? = nil, alert: TaskAlert? = nil,
                 creationDate: Date? = nil, lastModifiedDate: Date? = nil, sourceOrder: Int = 0) {
        self.id = id
        self.title = title
        self.notes = notes
        self.url = url
        self.listID = listID
        self.dueDate = dueDate
        self.hasDueTime = hasDueTime
        self.priority = priority
        self.isCompleted = isCompleted
        self.completionDate = completionDate
        self.recurrence = recurrence
        self.recurrenceRule = recurrenceRule
        self.alert = alert
        self.creationDate = creationDate
        self.lastModifiedDate = lastModifiedDate
        self.sourceOrder = sourceOrder
    }

    /// The task after `change`, with the invariants Reminders keeps:
    /// an empty title is refused, blank notes/URL become nil, and a repeat
    /// or time-relative alert can't outlive the date/time it hangs on.
    package func applying(_ change: TaskChange, now: Date = Date()) -> TaskItem { // swiftlint:disable:this cyclomatic_complexity - a case per change
        var task = self
        switch change {
        case .completed(let done):
            task.isCompleted = done
            task.completionDate = done ? now : nil
        case .title(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { task.title = trimmed }
        case .notes(let text):
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            task.notes = trimmed.isEmpty ? nil : text
        case .url(let url):
            task.url = url
        case .priority(let priority):
            task.priority = priority
        case .list(let id):
            task.listID = id
        case .recurrence(let recurrence):
            task.recurrence = dueDate == nil ? .never : recurrence
            // `.custom` means "left as it was"; a menu pick replaces the rule.
            if !task.recurrence.isCustom { task.recurrenceRule = TaskRecurrenceRule(standard: task.recurrence) }
        case .recurrenceRule(let rule):
            // A repeat needs a due date to hang on.
            task.recurrenceRule = dueDate == nil ? nil : rule
            task.recurrence = task.recurrenceRule?.menuValue ?? .never
        case .alert(let alert):
            // A relative alert needs a due time to be relative to.
            if case .relative = alert, !(dueDate != nil && hasDueTime) { break }
            task.alert = alert
        case .due(let date, let hasTime):
            task.dueDate = date
            task.hasDueTime = date != nil && hasTime
            if date == nil {
                task.recurrence = .never
                task.recurrenceRule = nil
            }
            if case .relative(let minutes)? = alert, date == nil || !task.hasDueTime {
                // Keep the alert as the same moment instead of losing it.
                if hasDueTime, let oldDue = dueDate {
                    task.alert = .absolute(oldDue.addingTimeInterval(-Double(minutes) * 60))
                } else {
                    task.alert = nil
                }
            }
        }
        return task
    }
}

/// Every edit Tasks makes to a reminder — one case per editable field.
package enum TaskChange: Sendable {
    case completed(Bool)
    case title(String)
    case notes(String?)
    case url(URL?)
    case due(Date?, hasTime: Bool)
    case recurrence(TaskRecurrence)
    /// An exact rule (Custom…, contextual presets); nil = never.
    case recurrenceRule(TaskRecurrenceRule?)
    case priority(TaskPriority)
    case list(String)
    case alert(TaskAlert?)
}
