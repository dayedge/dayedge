import SwiftUI
import UI

/// The kinds of change the app chat can make. "Always allow" is
/// remembered per kind — never for deletions.
package enum ChangeKind: String, Codable, CaseIterable, Sendable {
    case createTask, completeTask, updateTask, deleteTask
    case createEvent, updateEvent, deleteEvent

    package var isDestructive: Bool { self == .deleteTask || self == .deleteEvent }

    /// The card's heading.
    package var verb: String {
        switch self {
        case .createTask: return L10n.tr("changeproposal.create.task", "Create task")
        case .completeTask: return L10n.tr("changeproposal.complete.task", "Complete task")
        case .updateTask: return L10n.tr("changeproposal.change.task", "Change task")
        case .deleteTask: return L10n.tr("changeproposal.delete.task", "Delete task")
        case .createEvent: return L10n.tr("changeproposal.create.event", "Create event")
        case .updateEvent: return L10n.tr("changeproposal.change.event", "Change event")
        case .deleteEvent: return L10n.tr("changeproposal.delete.event", "Delete event")
        }
    }

    package func declinedReceipt(subject: String) -> String {
        switch self {
        case .createTask: return L10n.tr("receipt.declinedreceipt.createtask", "Declined: create task “\(subject)”")
        case .completeTask: return L10n.tr("receipt.declinedreceipt.completetask", "Declined: complete task “\(subject)”")
        case .updateTask: return L10n.tr("receipt.declinedreceipt.updatetask", "Declined: change task “\(subject)”")
        case .deleteTask: return L10n.tr("receipt.declinedreceipt.deletetask", "Declined: delete task “\(subject)”")
        case .createEvent: return L10n.tr("receipt.declinedreceipt.createevent", "Declined: create event “\(subject)”")
        case .updateEvent: return L10n.tr("receipt.declinedreceipt.updateevent", "Declined: change event “\(subject)”")
        case .deleteEvent: return L10n.tr("receipt.declinedreceipt.deleteevent", "Declined: delete event “\(subject)”")
        }
    }

    package func failedReceipt(subject: String) -> String {
        switch self {
        case .createTask: return L10n.tr("receipt.failedreceipt.createtask", "Couldn't create task “\(subject)”")
        case .completeTask: return L10n.tr("receipt.failedreceipt.completetask", "Couldn't complete task “\(subject)”")
        case .updateTask: return L10n.tr("receipt.failedreceipt.updatetask", "Couldn't change task “\(subject)”")
        case .deleteTask: return L10n.tr("receipt.failedreceipt.deletetask", "Couldn't delete task “\(subject)”")
        case .createEvent: return L10n.tr("receipt.failedreceipt.createevent", "Couldn't create event “\(subject)”")
        case .updateEvent: return L10n.tr("receipt.failedreceipt.updateevent", "Couldn't change event “\(subject)”")
        case .deleteEvent: return L10n.tr("receipt.failedreceipt.deleteevent", "Couldn't delete event “\(subject)”")
        }
    }

    package var symbol: String {
        switch self {
        case .createTask, .createEvent: return "plus.circle"
        case .completeTask: return "checkmark.circle"
        case .updateTask, .updateEvent: return "pencil.circle"
        case .deleteTask, .deleteEvent: return "trash"
        }
    }

    /// The split button's menu item.
    package var alwaysAllowTitle: String {
        switch self {
        case .createTask: return L10n.tr("changeproposal.always.allow.creating.tasks", "Always Allow Creating Tasks")
        case .completeTask: return L10n.tr("changeproposal.always.allow.completing.tasks", "Always Allow Completing Tasks")
        case .updateTask: return L10n.tr("changeproposal.always.allow.changing.tasks", "Always Allow Changing Tasks")
        case .createEvent: return L10n.tr("changeproposal.always.allow.creating.events", "Always Allow Creating Events")
        case .updateEvent: return L10n.tr("changeproposal.always.allow.changing.events", "Always Allow Changing Events")
        case .deleteTask, .deleteEvent: return ""
        }
    }

    /// Settings → Intelligence's list.
    package var settingsTitle: String {
        switch self {
        case .createTask: return L10n.tr("changeproposal.creating.tasks", "Creating tasks")
        case .completeTask: return L10n.tr("changeproposal.completing.tasks", "Completing tasks")
        case .updateTask: return L10n.tr("changeproposal.changing.tasks", "Changing tasks")
        case .createEvent: return L10n.tr("changeproposal.creating.events", "Creating events")
        case .updateEvent: return L10n.tr("changeproposal.changing.events", "Changing events")
        case .deleteTask: return L10n.tr("changeproposal.deleting.tasks", "Deleting tasks")
        case .deleteEvent: return L10n.tr("changeproposal.deleting.events", "Deleting events")
        }
    }
}

/// One field of an edit: "Time  10:30 → 15:00".
package struct ChangeField: Equatable, Sendable {
    package let label: String
    package let before: String?
    package let after: String?
    /// Stable machine wording when a displayed value differs (e.g. priority).
    package var assistantAfter: String?

    package init(label: String, before: String?, after: String?, assistantAfter: String? = nil) {
        self.label = label
        self.before = before
        self.after = after
        self.assistantAfter = assistantAfter == after ? nil : assistantAfter
    }

    package var reportValue: String { assistantAfter ?? after ?? "" }

    package func displayValue(_ value: String?) -> String? {
        guard let value else { return nil }
        if label == "Due", value == "No date" { return L10n.tr("approval.no.date", "No date") }
        if label == "Notes" || label == "Location", value == "None" { return L10n.tr("approval.none", "None") }
        return value
    }

    package var displayLabel: String {
        switch label {
        case "Title": return L10n.tr("approval.field.title", "Title")
        case "Due": return L10n.tr("approval.field.due", "Due")
        case "Priority": return L10n.tr("approval.field.priority", "Priority")
        case "List": return L10n.tr("approval.field.list", "List")
        case "Notes": return L10n.tr("approval.field.notes", "Notes")
        case "Time": return L10n.tr("approval.field.time", "Time")
        case "Calendar": return L10n.tr("approval.field.calendar", "Calendar")
        case "Location": return L10n.tr("approval.field.location", "Location")
        default: return label
        }
    }
}

/// A change the model wants to make, waiting for the user.
package struct ChangeProposal: Identifiable, Equatable, Sendable {
    package let id = UUID()
    package let kind: ChangeKind
    /// Overrides the kind's heading ("Mark task not done").
    package var headline: String?
    package let subject: ChangeSubject
    package var fields: [ChangeField] = []
    /// "This occurrence only", "Can't be undone".
    package var notes: [String] = []
    /// Remote models only, and never for deletions.
    package var offersAlwaysAllow = false
}

package enum ApprovalDecision: Equatable, Sendable {
    case allow, alwaysAllow, deny, cancelled
}

/// What became of a change: kept in the conversation, with Undo.
package struct ChatChangeReceipt: Identifiable, Equatable, Sendable {
    package enum State: Equatable, Sendable {
        case done
        case declined
        case failed(String)
        case undone
    }

    package let id: UUID
    package let kind: ChangeKind
    /// "Created “Faktura”".
    package var text: String
    /// "Tomorrow 15:00 · Reminders".
    package var detail: String?
    package var state: State
    package var canUndo: Bool

    package init(id: UUID = UUID(), kind: ChangeKind, text: String, detail: String? = nil, state: State, canUndo: Bool = false) {
        self.id = id
        self.kind = kind
        self.text = text
        self.detail = detail
        self.state = state
        self.canUndo = canUndo
    }
}

extension ChangeProposal {
    package var title: String { headline ?? kind.verb }
}
