import Foundation
import Domain

package enum TaskDuePreset: CaseIterable {
    case today, tomorrow, nextWeek, none

    package var title: String {
        switch self {
        case .today: return L10n.tr("taskcontextmenuplan.today", "Today")
        case .tomorrow: return L10n.tr("taskcontextmenuplan.tomorrow", "Tomorrow")
        case .nextWeek: return L10n.tr("taskcontextmenuplan.next.week", "Next Week")
        case .none: return L10n.tr("taskcontextmenuplan.no.date", "No Date")
        }
    }

    package func date(from now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .today: return today
        case .tomorrow: return calendar.date(byAdding: .day, value: 1, to: today)
        case .nextWeek: return calendar.date(byAdding: .day, value: 7, to: today)
        case .none: return nil
        }
    }
}

package enum TaskAction: Equatable {
    case complete
    case uncomplete
    case setPriority(TaskPriority)
    case setDue(TaskDuePreset)
    /// Opens Apple Reminders (external).
    case showInReminders
    /// Tasks view: jump to where the calendar shows this task (internal).
    case showInCalendar
    /// Calendar views: jump to the task itself in the Tasks view (internal).
    case showInTasks
    /// Calendar views, repeating tasks: same as a repeating event's.
    case previousOccurrence
    case nextOccurrence
    case copyTitle
    case delete

    /// The SF Symbol, as in the event menu; the submenus' choices have none.
    package var symbolName: String? {
        switch self {
        case .complete: return "checkmark.circle"
        case .uncomplete: return "circle"
        case .setPriority, .setDue: return nil
        case .showInReminders: return "checklist"
        case .showInCalendar: return ViewMode.day.symbolName
        case .showInTasks: return ViewMode.tasks.symbolName
        case .nextOccurrence: return "arrow.right"
        case .previousOccurrence: return "arrow.left"
        case .copyTitle: return "doc.on.doc"
        case .delete: return "trash"
        }
    }
}

/// What the task context menu offers, as data (mirrors `EventContextMenuPlan`).
package enum TaskMenuEntry: Equatable {
    case action(TaskAction)
    /// `checked`: the choice that is the task's current value (shown with
    /// the menu's checkmark), when there is one.
    case submenu(title: String, symbol: String, actions: [TaskAction], checked: TaskAction?)
    case divider
}

package enum TaskContextMenuPlan {
    /// Where the menu is shown: the Tasks view, or a calendar view (agenda,
    /// day), which adds occurrence navigation like a repeating event's.
    package enum Context {
        case tasks
        case calendar
    }

    /// The event menu's grouping: completion; the task's properties;
    /// showing it elsewhere (in DayEdge, then Reminders) and Copy Title; in a
    /// calendar view a repeating task's occurrences (next first); deleting.
    /// A read-only list's reminders can be looked at and copied, not changed.
    package static func entries(for task: TaskItem, isReadOnly: Bool = false, context: Context = .tasks) -> [TaskMenuEntry] {
        let completion: [TaskMenuEntry] = [.action(task.isCompleted ? .uncomplete : .complete)]
        let properties: [TaskMenuEntry] = [
            .submenu(title: L10n.tr("taskcontextmenuplan.priority", "Priority"), symbol: "flag",
                     actions: TaskPriority.allCases.map { .setPriority($0) }, checked: .setPriority(task.priority)),
            // Relative presets: no check — "Today" stops matching tomorrow.
            .submenu(title: L10n.tr("taskcontextmenuplan.due", "Due Date"), symbol: "calendar.badge.clock",
                     actions: TaskDuePreset.allCases.map { .setDue($0) }, checked: nil)
        ]
        let showElsewhere: [TaskMenuEntry] = switch context {
        case .calendar: [.action(.showInTasks)]
        case .tasks: task.dueDate != nil && !task.isCompleted ? [.action(.showInCalendar)] : []
        }
        let navigation = showElsewhere + [.action(.showInReminders), .action(.copyTitle)]
        let occurrences: [TaskMenuEntry] = context == .calendar && task.effectiveRecurrenceRule != nil && !task.isCompleted
            ? [.action(.nextOccurrence), .action(.previousOccurrence)] : []

        let groups = isReadOnly ? [navigation, occurrences] : [completion, properties, navigation, occurrences, [.action(.delete)]]
        return Array(groups.filter { !$0.isEmpty }.joined(separator: [.divider]))
    }

    // swiftlint:disable:next cyclomatic_complexity - one title per TaskAction
    package static func title(for action: TaskAction) -> String {
        switch action {
        case .complete: return L10n.tr("taskcontextmenuplan.mark.as.completed", "Mark as Completed")
        case .uncomplete: return L10n.tr("taskcontextmenuplan.mark.as.not.completed", "Mark as Incomplete")
        case .setPriority(let priority): return priority.title
        case .setDue(let preset): return preset.title
        case .showInReminders: return L10n.tr("taskcontextmenuplan.open.in.reminders", "Open in Reminders")
        case .showInTasks: return L10n.tr("taskcontextmenuplan.show.in.tasks", "Show in Tasks")
        case .showInCalendar: return L10n.tr("taskcontextmenuplan.show.in.calendar", "Show in Calendar")
        case .previousOccurrence: return L10n.tr("taskcontextmenuplan.go.to.previous.occurrence", "Go to Previous Occurrence")
        case .nextOccurrence: return L10n.tr("taskcontextmenuplan.go.to.next.occurrence", "Go to Next Occurrence")
        case .copyTitle: return L10n.tr("taskcontextmenuplan.copy.title", "Copy Title")
        case .delete: return L10n.tr("taskcontextmenuplan.delete.reminder", "Delete Task…")
        }
    }
}
