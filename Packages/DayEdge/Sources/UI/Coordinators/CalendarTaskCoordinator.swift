import Foundation
import Observation

/// Task selection and the Task Details popover inside the calendar views
/// (agenda and day). The calendar's counterpart of the event side of
/// `EventDetailCoordinator`; what a task *does* lives in `TaskActions`.
@MainActor
@Observable
package final class CalendarTaskCoordinator {
    package let actions: TaskActions
    /// One task on one day. A repeating task can appear on several days at
    /// once, and only the occurrence that was opened shows its details.
    package struct Occurrence: Hashable {
        package let taskID: String
        package let day: Date

        package init(taskID: String, day: Date, calendar: Calendar = .autoupdatingCurrent) {
            self.taskID = taskID
            self.day = calendar.startOfDay(for: day)
        }
    }

    package private(set) var selection: AgendaTaskSelection?
    package private(set) var presented: Occurrence?

    package init(actions: TaskActions) {
        self.actions = actions
    }

    package func select(_ selection: AgendaTaskSelection?) {
        self.selection = selection
    }

    package func isSelected(_ taskID: String) -> Bool { selection?.taskID == taskID }

    package func isPresented(_ occurrence: Occurrence) -> Bool { presented == occurrence }

    package func toggleDetail(for occurrence: Occurrence) {
        presented = presented == occurrence ? nil : occurrence
    }

    package func setDetailPresented(_ isPresented: Bool, for occurrence: Occurrence) {
        if isPresented { presented = occurrence } else if presented == occurrence { presented = nil }
    }

    /// Return: the selected task's details. False when no task is selected,
    /// so the caller can fall through to events.
    @discardableResult
    package func openSelectedDetails() -> Bool {
        guard let selection else { return false }
        toggleDetail(for: Occurrence(taskID: selection.taskID, day: selection.date))
        return true
    }

    /// Escape. True when a popover was open and is now closed.
    @discardableResult
    package func dismissDetail() -> Bool {
        guard presented != nil else { return false }
        presented = nil
        return true
    }

    /// Completing from anywhere closes that task's popover: once it's done,
    /// it leaves the calendar.
    package func complete(_ taskID: String) {
        guard actions.setCompleted(true, taskID: taskID) else { return }
        if presented?.taskID == taskID { presented = nil }
    }
}
