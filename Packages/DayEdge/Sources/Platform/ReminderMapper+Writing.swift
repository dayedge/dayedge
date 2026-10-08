import EventKit
import Foundation
import Domain

extension ReminderMapper {
    // MARK: Writing

    // swiftlint:disable cyclomatic_complexity - a case per TaskChange, mirroring TaskItem.applying
    /// Applies `change` to `reminder` the way `TaskItem.applying` would to
    /// the model — same invariants — writing only the affected fields.
    /// Throws `.readOnlyList` for a move into a list that can't be edited.
    package static func write(_ change: TaskChange, to reminder: EKReminder, calendar: Calendar, eventStore: EKEventStore, now: Date = Date()) throws {
        let before = taskItem(from: reminder, calendar: calendar)
        let after = before.applying(change, now: now)

        switch change {
        case .completed(let done):
            reminder.isCompleted = done
        case .title:
            if after.title != before.title { reminder.title = after.title }
        case .notes:
            reminder.notes = after.notes
        case .url:
            reminder.url = after.url
        case .priority:
            reminder.priority = eventKitPriority(after.priority)
        case .list(let id):
            guard let target = eventStore.calendars(for: .reminder).first(where: { $0.calendarIdentifier == id }) else {
                throw TaskSourceError.notFound
            }
            guard target.allowsContentModifications else { throw TaskSourceError.readOnlyList }
            reminder.calendar = target
        case .recurrence(let recurrence):
            // `.custom` means "leave it": the user hasn't picked anything.
            if case .custom = recurrence { break }
            setRecurrence(after.recurrence, on: reminder)
        case .recurrenceRule:
            for rule in reminder.recurrenceRules ?? [] { reminder.removeRecurrenceRule(rule) }
            if let rule = after.recurrenceRule { reminder.addRecurrenceRule(ekRule(from: rule)) }
        case .alert:
            setAlert(after.alert, on: reminder)
        case .due:
            if let date = after.dueDate {
                reminder.dueDateComponents = dueComponents(for: date, hasTime: after.hasDueTime, calendar: calendar)
            } else {
                reminder.dueDateComponents = nil
            }
            // A repeat can't outlive its due date.
            if after.recurrence == .never, before.recurrence != .never { setRecurrence(.never, on: reminder) }
            if after.alert != before.alert { setAlert(after.alert, on: reminder) }
        }
    }
    // swiftlint:enable cyclomatic_complexity

    private static func setRecurrence(_ recurrence: TaskRecurrence, on reminder: EKReminder) {
        for rule in reminder.recurrenceRules ?? [] { reminder.removeRecurrenceRule(rule) }
        if let rule = rule(for: recurrence) { reminder.addRecurrenceRule(rule) }
    }

    /// Copies a new reminder's fields from `draft`.
    package static func fill(_ reminder: EKReminder, from draft: TaskDraft, calendar: Calendar) {
        reminder.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.notes = draft.notes
        reminder.priority = eventKitPriority(draft.priority)
        if let due = draft.dueDate {
            reminder.dueDateComponents = dueComponents(for: due, hasTime: draft.hasDueTime, calendar: calendar)
            // A repeat needs a due date to hang on (as in `TaskItem`).
            if let rule = draft.recurrenceRule { reminder.addRecurrenceRule(ekRule(from: rule)) }
        }
        if let alert = draft.alert { setAlert(alert, on: reminder) }
    }

    /// The EventKit rule for a `TaskRecurrenceRule` — the inverse of
    /// `rule(from:)`.
    package static func ekRule(from rule: TaskRecurrenceRule) -> EKRecurrenceRule {
        let frequency: EKRecurrenceFrequency
        switch rule.frequency {
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        }
        let days = rule.weekdays.compactMap { day in
            EKWeekday(rawValue: day.weekday).map { EKRecurrenceDayOfWeek($0, weekNumber: day.ordinal) }
        }
        let end: EKRecurrenceEnd? = rule.endDate.map { EKRecurrenceEnd(end: $0) }
            ?? rule.occurrenceCount.map { EKRecurrenceEnd(occurrenceCount: $0) }
        func numbers(_ values: [Int]) -> [NSNumber]? { values.isEmpty ? nil : values.map { NSNumber(value: $0) } }
        return EKRecurrenceRule(
            recurrenceWith: frequency, interval: rule.interval,
            daysOfTheWeek: days.isEmpty ? nil : days, daysOfTheMonth: numbers(rule.daysOfMonth),
            monthsOfTheYear: numbers(rule.months), weeksOfTheYear: nil, daysOfTheYear: nil,
            setPositions: numbers(rule.setPositions), end: end
        )
    }
}
