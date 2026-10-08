import Foundation
import Domain

/// What the app chat may change, once the user has approved — the one seam
/// between the change tools and the app's data (a fake in tests).
package protocol AssistantChangeWriter: Sendable {
    func createTask(_ draft: TaskDraft) async throws -> TaskItem
    func changeTask(_ change: TaskChange, taskID: String) async throws
    func deleteTask(_ taskID: String) async throws
    func eventCalendars() async -> [WritableCalendar]
    func createEvent(_ draft: EventDraft) async throws -> EventSnapshot
    func updateEvent(_ target: EventEditReference, _ change: EventChange) async throws -> (before: EventSnapshot, after: EventSnapshot)
    func deleteEvent(_ target: EventEditReference) async throws -> EventSnapshot
}

package enum AssistantChangeFailure: Error, Equatable {
    case taskGone
    case readOnlyList

    package static func displayMessage(_ error: Error) -> String {
        switch error {
        case AssistantChangeFailure.taskGone: return L10n.tr("assistant.task.gone", "That task can't be found any more")
        case AssistantChangeFailure.readOnlyList: return L10n.tr("assistant.list.read.only", "That list can't be changed")
        default: return WriteFailureText.message(error)
        }
    }

    package static func message(_ error: Error) -> String {
        switch error {
        case AssistantChangeFailure.taskGone: return "that task can't be found any more"
        case AssistantChangeFailure.readOnlyList: return "that list can't be changed"
        default: return WriteFailureText.message(error, locale: Locale(identifier: "en"))
        }
    }
}

/// The app's data: tasks through the same repository every view uses (so
/// Tasks, the calendar and the menu bar update as usual), events through
/// `CalendarEventEditing`. No global toast — the chat's receipt says it,
/// with its own Undo.
@MainActor
package final class AppAssistantChangeWriter: AssistantChangeWriter {
    private let tasks: TaskRepository
    private let events: CalendarEventEditing

    package init(tasks: TaskRepository, events: CalendarEventEditing) {
        self.tasks = tasks
        self.events = events
    }

    package func createTask(_ draft: TaskDraft) async throws -> TaskItem {
        if let listID = draft.listID, tasks.lists.first(where: { $0.id == listID })?.allowsModifications == false {
            throw AssistantChangeFailure.readOnlyList
        }
        return try await tasks.create(draft)
    }

    package func changeTask(_ change: TaskChange, taskID: String) async throws {
        try writable(taskID)
        try await tasks.applyAndWait(change, toTaskID: taskID)
    }

    package func deleteTask(_ taskID: String) async throws {
        try writable(taskID)
        try await tasks.deleteAndWait(taskID: taskID)
    }

    package func eventCalendars() async -> [WritableCalendar] { await events.writableCalendars() }

    package func createEvent(_ draft: EventDraft) async throws -> EventSnapshot { try await events.create(draft) }

    package func updateEvent(_ target: EventEditReference, _ change: EventChange) async throws -> (before: EventSnapshot, after: EventSnapshot) {
        try await events.update(target, change)
    }

    package func deleteEvent(_ target: EventEditReference) async throws -> EventSnapshot { try await events.delete(target) }

    /// Checked again at the moment of writing.
    private func writable(_ taskID: String) throws {
        guard let task = tasks.tasks.first(where: { $0.id == taskID }) else { throw AssistantChangeFailure.taskGone }
        if tasks.lists.first(where: { $0.id == task.listID })?.allowsModifications == false {
            throw AssistantChangeFailure.readOnlyList
        }
    }
}
