import SwiftUI
import Domain
import UI

/// `create_task`, `complete_task`, `update_task`, `delete_task`. Each one
/// resolves and checks first (problems go back to the model as text), then
/// asks the user through the chat's card (`ChangeRunner`).
package enum TaskChangeTools {
    package static let taskArgument = "The task: its reference from a result (like T3), or its exact title."
    package static let priorities = ["none", "low", "medium", "high"]

    package static func make(_ context: AssistantToolContext) -> [AssistantTool] {
        [create(context), complete(context), update(context), delete(context)]
    }

    // MARK: - create_task

    package static func create(_ context: AssistantToolContext) -> AssistantTool {
        .answering(
            name: "create_task",
            description: context.brief("Create a task (reminder). The user approves it in the app before it's created.", "Create a task."),
            parameters: context.parameters([
                .init(name: "title", kind: .string, description: "What to do."),
                .init(name: "due", kind: .string,
                      description: context.brief("When it's due: \(AssistantMoment.accepted). Omit for no date.", "Day and time, e.g. tomorrow 10:00."),
                      isRequired: false)
            ], optional: [
                .init(name: "list", kind: .string, description: "The list's name. Omit for the default list.", isRequired: false),
                .init(name: "priority", kind: .string, description: "Priority.", isRequired: false, enumValues: priorities),
                .init(name: "notes", kind: .string, description: "Notes.", isRequired: false)
            ])
        ) { arguments in
            let title = try arguments.string("title").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, let changes = context.changes else { return "A task needs a title." }
            let snapshot = await context.data.taskSnapshot()
            let due = try await arguments.optionalString("due").flatMap(nonEmpty).asyncMap { try await AssistantMoment.resolve($0, context: context) }
            var list: CalendarSource?
            if let name = arguments.optionalString("list").flatMap(nonEmpty) {
                guard let match = matchList(name, in: snapshot.lists) else {
                    let names = snapshot.lists.filter(\.allowsModifications).map(\.title).joined(separator: ", ")
                    return "There's no list called “\(name)”. Lists: \(names)."
                }
                list = match
            }
            let priority = arguments.optionalString("priority").flatMap(priority(named:)) ?? TaskPriority.none
            let notes = arguments.optionalString("notes").flatMap(nonEmpty)
            let draft = TaskDraft(title: title, listID: list?.id, dueDate: due?.date, hasDueTime: due?.hasTime ?? false,
                                  priority: priority, notes: notes)

            let now = context.now()
            let calendar = context.calendar
            let dueText = due.map { ChangeRunner.when($0.date, hasTime: $0.hasTime, now: now, calendar: calendar, format: context.timeFormat()) }
            let proposal = ChangeProposal(
                kind: .createTask,
                subject: ChangeSubject(marker: .ring(list?.color ?? .secondary), title: title,
                                       detail: ChangeRunner.joined(dueText, list?.title, priority == .none ? nil : "\(priority.title) priority")),
                offersAlwaysAllow: context.offersAlwaysAllow
            )
            return await ChangeRunner.run(proposal, context: context) {
                let item = try await changes.createTask(draft)
                let listName = await context.data.taskSnapshot().listName(for: item)
                return .init(
                    text: L10n.tr("taskchangetools.created", "Created “\(String(describing: item.title))”"),
                    detail: ChangeRunner.joined(dueText, listName),
                    undo: { try await changes.deleteTask(item.id) },
                    report: "Done — created:\n" + context.taskLine(item, day: nil, list: listName)
                )
            }
        }
    }

    // MARK: - complete_task

    package static func complete(_ context: AssistantToolContext) -> AssistantTool {
        .answering(
            name: "complete_task",
            description: context.brief("Mark a task done (or not done again). The user approves it in the app.", "Mark a task done."),
            parameters: context.parameters([
                .init(name: "task", kind: .string, description: context.brief(taskArgument, "The task's title."))
            ], optional: [
                .init(name: "done", kind: .boolean, description: "true = done (default), false = not done.", isRequired: false)
            ])
        ) { arguments in
            guard let changes = context.changes else { return "Changes aren't available here." }
            let done = (try? arguments.bool("done")) ?? true
            let target = await AssistantTargetResolver.task(try arguments.string("task"), includeCompleted: !done, context: context)
            guard case .found(let (task, list)) = target else { return unresolved(target) }
            if task.isCompleted == done { return "“\(task.title)” is already \(done ? "done" : "not done")." }
            if list?.allowsModifications == false { return "“\(task.title)” is in a list that can't be changed." }
            var proposal = ChangeProposal(
                kind: .completeTask,
                headline: done ? nil : L10n.tr("taskchangetools.mark.task.not.done", "Mark task not done"),
                subject: subject(task, list: list, context: context),
                offersAlwaysAllow: context.offersAlwaysAllow
            )
            if done, task.isRecurring { proposal.notes = [L10n.tr("taskchangetools.it.repeats.the.next.one.stays", "It repeats — the next one stays.")] }
            return await ChangeRunner.run(proposal, context: context) {
                try await changes.changeTask(.completed(done), taskID: task.id)
                return .init(
                    text: done ? L10n.tr(
                        "taskchangetools.completed", "Completed “\(String(describing: task.title))”"
                    ) : L10n.tr(
                        "taskchangetools.marked.not.done", "Marked “\(String(describing: task.title))” not done"
                    ),
                    undo: { try await changes.changeTask(.completed(!done), taskID: task.id) },
                    report: "Done — “\(task.title)” is marked \(done ? "done" : "not done")."
                )
            }
        }
    }

    // MARK: - update_task

    // swiftlint:disable:next cyclomatic_complexity function_body_length - one branch per optional argument the model may pass
    package static func update(_ context: AssistantToolContext) -> AssistantTool {
        .answering(
            name: "update_task",
            description: context.brief("Change a task's title, due date, priority, list or notes. Only pass what changes. The user approves it in the app.",
                                       "Change a task's due date or title."),
            parameters: context.parameters([
                .init(name: "task", kind: .string, description: context.brief(taskArgument, "The task's title.")),
                .init(name: "due", kind: .string,
                      description: context.brief("New due date: \(AssistantMoment.accepted), or 'none' to remove it.", "New day and time."),
                      isRequired: false),
                .init(name: "title", kind: .string, description: "New title.", isRequired: false)
            ], optional: [
                .init(name: "priority", kind: .string, description: "New priority.", isRequired: false, enumValues: priorities),
                .init(name: "list", kind: .string, description: "Move to the list with this name.", isRequired: false),
                .init(name: "notes", kind: .string, description: "New notes ('none' to remove them).", isRequired: false)
            ])
        ) { arguments in
            guard let changes = context.changes else { return "Changes aren't available here." }
            let target = await AssistantTargetResolver.task(try arguments.string("task"), includeCompleted: true, context: context)
            guard case .found(let (task, list)) = target else { return unresolved(target) }
            if list?.allowsModifications == false { return "“\(task.title)” is in a list that can't be changed." }
            let now = context.now()
            let calendar = context.calendar
            let snapshot = await context.data.taskSnapshot()

            var apply: [TaskChange] = []
            var revert: [TaskChange] = []
            var fields: [ChangeField] = []
            if let title = arguments.optionalString("title").flatMap(nonEmpty), title != task.title {
                apply.append(.title(title)); revert.append(.title(task.title))
                fields.append(ChangeField(label: "Title", before: task.title, after: title))
            }
            if let due = arguments.optionalString("due").flatMap(nonEmpty) {
                let old = task.dueDate.map { ChangeRunner.when($0, hasTime: task.hasDueTime, now: now, calendar: calendar, format: context.timeFormat()) }
                if isNone(due) {
                    apply.append(.due(nil, hasTime: false))
                    fields.append(ChangeField(label: "Due", before: old, after: "No date"))
                } else {
                    let moment = try await AssistantMoment.resolve(due, on: task.dueDate, context: context)
                    apply.append(.due(moment.date, hasTime: moment.hasTime))
                    fields.append(ChangeField(label: "Due", before: old ?? "No date",
                                              after: ChangeRunner.when(moment.date, hasTime: moment.hasTime, now: now, calendar: calendar, format: context.timeFormat()),
                                              assistantAfter: ChangeRunner.when(moment.date, hasTime: moment.hasTime, now: now, calendar: calendar,
                                                                                format: .twentyFourHour, locale: Locale(identifier: "en"))))
                }
                revert.append(.due(task.dueDate, hasTime: task.hasDueTime))
                if task.isRecurring, isNone(due) { revert.append(.recurrence(task.recurrence)) }
            }
            if let name = arguments.optionalString("priority"), let priority = priority(named: name), priority != task.priority {
                apply.append(.priority(priority)); revert.append(.priority(task.priority))
                fields.append(ChangeField(label: "Priority", before: task.priority.title, after: priority.title, assistantAfter: priority.assistantValue.capitalized))
            }
            if let name = arguments.optionalString("list").flatMap(nonEmpty) {
                guard let target = matchList(name, in: snapshot.lists) else { return "There's no list called “\(name)”." }
                if target.id != task.listID {
                    apply.append(.list(target.id)); revert.append(.list(task.listID))
                    fields.append(ChangeField(label: "List", before: list?.title, after: target.title))
                }
            }
            if let notes = arguments.optionalString("notes") {
                let new: String? = isNone(notes) ? nil : notes
                if new != task.notes {
                    apply.append(.notes(new)); revert.append(.notes(task.notes))
                    fields.append(ChangeField(label: "Notes", before: task.notes, after: new ?? "None"))
                }
            }
            guard !apply.isEmpty else { return "Nothing to change on “\(task.title)”." }

            let proposal = ChangeProposal(
                kind: .updateTask,
                subject: subject(task, list: list, context: context),
                fields: fields,
                offersAlwaysAllow: context.offersAlwaysAllow
            )
            let changeList = apply
            let revertList = revert
            let finalFields = fields
            return await ChangeRunner.run(proposal, context: context) {
                try await applyAll(changeList, reverting: revertList, taskID: task.id, changes: changes)
                let summary = finalFields.map { "\($0.label.lowercased()) \($0.reportValue)" }.joined(separator: ", ")
                return .init(
                    text: L10n.tr("taskchangetools.changed", "Changed “\(String(describing: task.title))”"),
                    detail: finalFields.map { "\($0.displayLabel): \($0.displayValue($0.after) ?? "")" }.joined(separator: ", "),
                    undo: { for change in revertList { try await changes.changeTask(change, taskID: task.id) } },
                    report: "Done — “\(task.title)”: \(summary)."
                )
            }
        }
    }

    /// One field at a time (a `TaskChange` is one field): if one fails, the
    /// ones already saved are put back, so the receipt's "Couldn't change"
    /// is true of the whole change.
    private static func applyAll(_ changeList: [TaskChange], reverting revertList: [TaskChange], taskID: String,
                                 changes: any AssistantChangeWriter) async throws {
        var saved = 0
        do {
            for change in changeList {
                try await changes.changeTask(change, taskID: taskID)
                saved += 1
            }
        } catch {
            for change in revertList.prefix(saved).reversed() { try? await changes.changeTask(change, taskID: taskID) }
            throw error
        }
    }

    // MARK: - delete_task

    package static func delete(_ context: AssistantToolContext) -> AssistantTool {
        .answering(
            name: "delete_task",
            description: context.brief("Delete a task. The user approves it in the app.", "Delete a task."),
            parameters: [.init(name: "task", kind: .string, description: context.brief(taskArgument, "The task's title."))]
        ) { arguments in
            guard let changes = context.changes else { return "Changes aren't available here." }
            let target = await AssistantTargetResolver.task(try arguments.string("task"), includeCompleted: true, context: context)
            guard case .found(let (task, list)) = target else { return unresolved(target) }
            if list?.allowsModifications == false { return "“\(task.title)” is in a list that can't be changed." }
            var proposal = ChangeProposal(kind: .deleteTask, subject: subject(task, list: list, context: context))
            if task.isRecurring { proposal.notes = [L10n.tr("taskchangetools.deletes.the.task.with.all.its.repeats", "Deletes the task with all its repeats.")] }
            let restore = TaskDraft(title: task.title, listID: task.listID, dueDate: task.dueDate, hasDueTime: task.hasDueTime,
                                    priority: task.priority, notes: task.notes, recurrenceRule: task.effectiveRecurrenceRule,
                                    alert: task.alert)
            return await ChangeRunner.run(proposal, context: context) {
                try await changes.deleteTask(task.id)
                return .init(
                    text: L10n.tr("taskchangetools.deleted", "Deleted “\(String(describing: task.title))”"),
                    undo: { _ = try await changes.createTask(restore) },
                    report: "Done — “\(task.title)” is deleted."
                )
            }
        }
    }

    // MARK: -

    package static func subject(_ task: TaskItem, list: CalendarSource?, context: AssistantToolContext) -> ChangeSubject {
        let due = task.dueDate.map { ChangeRunner.when($0, hasTime: task.hasDueTime, now: context.now(), calendar: context.calendar, format: context.timeFormat()) }
        return ChangeSubject(marker: .ring(list?.color ?? .secondary), title: task.title,
                             detail: ChangeRunner.joined(due, list?.title))
    }

    package static func unresolved<T>(_ outcome: AssistantTargetResolver.Outcome<T>) -> String {
        if case .unresolved(let text) = outcome { return text }
        return "Couldn't find it."
    }

    package static func matchList(_ name: String, in lists: [CalendarSource]) -> CalendarSource? {
        AssistantTargetResolver.titleMatches(name, in: lists, title: \.title).first
    }

    package static func priority(named name: String) -> TaskPriority? {
        TaskPriority.allCases.first { $0.assistantValue == name.lowercased() }
    }

    package static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    package static func isNone(_ text: String) -> Bool {
        ["none", "no date", "nothing", "remove", "clear", "-"].contains(text.lowercased().trimmingCharacters(in: .whitespaces))
    }
}

extension Optional {
    /// `map` for an async, throwing transform.
    package func asyncMap<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        guard let self else { return nil }
        return try await transform(self)
    }
}
