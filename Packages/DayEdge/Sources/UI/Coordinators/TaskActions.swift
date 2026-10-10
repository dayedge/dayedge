import AppKit
import Foundation
import Domain

/// What can be done to a task — complete, edit, delete, reveal, copy —
/// shared by every view that shows one (the Tasks tab, the agenda, the day
/// view), so a task behaves the same wherever it appears. Presentation
/// state (selection, popovers, lingering rows) stays with each view's own
/// coordinator.
@MainActor
package final class TaskActions {
    package let repository: TaskRepository

    package init(repository: TaskRepository) {
        self.repository = repository
    }

    private var noticeCenter: NoticeCenter? { repository.noticeCenter }

    /// Takes the calendar to a task on a day. `showingCalendar` asks to
    /// switch to it first (from the Tasks view). Set by the root view.
    package var navigate: ((_ taskID: String, _ day: Date, _ showingCalendar: Bool) -> Void)?
    /// Takes the Tasks view to a task and selects it; false when Tasks
    /// doesn't hold it. Set by the root view.
    package var revealInTasks: ((_ taskID: String) -> Bool)?

    package func task(_ id: String) -> TaskItem? { repository.tasks.first { $0.id == id } }

    package func list(for task: TaskItem) -> CalendarSource? { repository.lists.first { $0.id == task.listID } }

    /// Reminders in a read-only list (shared without edit rights, say) can
    /// be looked at but not changed.
    package func isReadOnly(_ task: TaskItem) -> Bool {
        list(for: task).map { !$0.allowsModifications } ?? false
    }

    /// Marks done or not done. Completing announces itself with Undo;
    /// `undo` defaults to simply marking it not done again.
    @discardableResult
    package func setCompleted(_ done: Bool, taskID id: String, undo: (() -> Void)? = nil) -> Bool {
        guard let task = task(id), !isReadOnly(task), task.isCompleted != done else { return false }
        repository.apply(.completed(done), toTaskID: id)
        if done {
            let undo = undo ?? { [weak self] in self?.setCompleted(false, taskID: id) }
            noticeCenter?.show(.success(title: L10n.tr(
                "taskactions.task.completed", "Task completed"
            ), action: NoticeAction(title: L10n.tr(
                "taskactions.undo", "Undo"
            ), handler: undo)))
        }
        return true
    }

    /// Quick Add: creates the reminder and says so, with Undo (which
    /// deletes it again). A failure is reported to the user and rethrown,
    /// so the caller can keep the draft.
    @discardableResult
    package func create(_ draft: TaskDraft) async throws -> TaskItem {
        do {
            let item = try await repository.create(draft)
            noticeCenter?.show(.success(
                title: L10n.tr("taskactions.task.created", "Task created"),
                action: NoticeAction(title: L10n.tr("taskactions.undo", "Undo")) { [weak self] in self?.repository.delete(taskID: item.id) }
            ))
            return item
        } catch {
            let failure = (error as? TaskSourceError) ?? .saveFailed(error.localizedDescription)
            noticeCenter?.show(.error(title: L10n.tr("taskactions.couldn.t.create.reminder", "Couldn't create task"), message: failure.message))
            throw failure
        }
    }

    /// The one way a reminder's fields change — from the details popover
    /// and the context menu alike.
    package func edit(_ change: TaskChange, taskID id: String) {
        guard let task = task(id), !isReadOnly(task) else { return }
        repository.apply(change, toTaskID: id)
    }

    /// Deleting just happens — Undo puts the task back (re-created with the
    /// same details, repeat and alert), so nothing needs confirming.
    package func requestDeletion(of task: TaskItem, onDeleted: @escaping () -> Void = {}) {
        if delete(task.id) { onDeleted() }
    }

    @discardableResult
    package func delete(_ id: String) -> Bool {
        guard let task = task(id), !isReadOnly(task) else { return false }
        repository.delete(taskID: id)
        let restore = TaskDraft(
            title: task.title, listID: task.listID, dueDate: task.dueDate, hasDueTime: task.hasDueTime,
            priority: task.priority, notes: task.notes, recurrenceRule: task.effectiveRecurrenceRule, alert: task.alert
        )
        noticeCenter?.show(.success(
            title: L10n.tr("taskactions.task.deleted", "Task deleted"),
            action: NoticeAction(title: L10n.tr("taskactions.undo", "Undo")) { [weak self] in
                guard let self else { return }
                Task { _ = try? await self.repository.create(restore) }
            }
        ))
        return true
    }

    /// Previous / next occurrence of a repeating task, from the day it is
    /// shown on — the same interaction, notice and wording as for events.
    package func goToOccurrence(of task: TaskItem, from day: Date, direction: OccurrenceDirection,
                                now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) {
        let current = self.task(task.id) ?? task // the real task, not a projected copy
        if let target = TaskOccurrenceNavigation.adjacentDay(for: current, from: day, direction: direction, now: now, calendar: calendar) {
            navigate?(task.id, target, false)
        } else {
            noticeCenter?.show(.information(
                title: direction == .next ? L10n.tr(
                    "taskactions.no.next.occurrence.found", "No next occurrence found"
                ) : L10n.tr(
                    "taskactions.no.previous.occurrence.found", "No previous occurrence found"
                )
            ))
        }
    }

    /// Calendar → the Tasks view: the task itself (not an occurrence), in
    /// its own section, selected.
    package func showInTasks(_ task: TaskItem) {
        guard revealInTasks?(task.id) == true else {
            noticeCenter?.show(.information(title: L10n.tr("taskactions.not.shown.in.tasks", "Not shown in Tasks")))
            return
        }
    }

    /// Tasks view → the calendar, on the day it shows this task.
    package func showInCalendar(_ task: TaskItem, now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) {
        guard let day = TaskOccurrenceNavigation.shownDay(of: task, now: now, calendar: calendar) else { return }
        navigate?(task.id, day, true)
    }

    // swiftlint:disable cyclomatic_complexity - one case per TaskAction
    /// Context-menu actions. Completion is left to the caller, which knows
    /// how its view should react (the Tasks tab lets a row linger). `day`
    /// is the day a calendar view shows the task on.
    package func perform(_ action: TaskAction, on task: TaskItem, day: Date? = nil, now: Date = Date(),
                         calendar: Calendar = .autoupdatingCurrent, onDeleted: @escaping () -> Void = {}) {
        switch action {
        case .complete: setCompleted(true, taskID: task.id)
        case .uncomplete: setCompleted(false, taskID: task.id)
        case .setPriority(let priority): edit(.priority(priority), taskID: task.id)
        case .setDue(let preset): edit(.due(preset.date(from: now, calendar: calendar), hasTime: false), taskID: task.id)
        case .showInReminders: repository.revealInSourceApp(taskID: task.id)
        case .showInCalendar: showInCalendar(task, now: now, calendar: calendar)
        case .showInTasks: showInTasks(task)
        case .previousOccurrence, .nextOccurrence:
            guard let day else { return }
            goToOccurrence(of: task, from: day, direction: action == .nextOccurrence ? .next : .previous, now: now, calendar: calendar)
        case .copyTitle:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(task.title, forType: .string)
        case .delete: requestDeletion(of: task, onDeleted: onDeleted)
        }
    }
    // swiftlint:enable cyclomatic_complexity
}
