import Foundation
import Domain

/// Quick Add's Repeat and End Repeat, for tasks and events alike: the Repeat menu's value, a parsed rule the menu
/// can't express, and the last day. How often and until when are kept apart, so choosing another Repeat keeps the end,
/// as in Calendar and Reminders.
package struct RepeatEdit: Equatable {
    package var recurrence: TaskRecurrence
    /// The parsed rule, without its end, while `recurrence` shows it.
    package var customRule: TaskRecurrenceRule?
    /// End Repeat: the last day (inclusive), at its start; nil is Never.
    package var lastDay: Date?

    package init(rule: TaskRecurrenceRule?, calendar: Calendar) {
        let often = rule?.withoutEnd
        recurrence = often?.menuValue ?? .never
        customRule = recurrence.isCustom ? often : nil
        lastDay = rule?.endDate.map { calendar.startOfDay(for: $0) }
    }

    package var isRepeating: Bool { recurrence.isRepeating }

    /// The menu's values, plus the parsed rule it can't express while that is selected.
    package var options: [TaskRecurrence] {
        recurrence.isCustom ? TaskRecurrence.standard + [recurrence] : TaskRecurrence.standard
    }

    /// The rule to save for a series whose first day is `firstDay`: none when it does not repeat. An end before the
    /// first day is no end.
    package func rule(firstDay: Date, calendar: Calendar) -> TaskRecurrenceRule? {
        let rule = recurrence.isCustom ? customRule : TaskRecurrenceRule(standard: recurrence)
        let end = lastDay.flatMap { $0 >= calendar.startOfDay(for: firstDay) ? $0 : nil }
        return rule?.ending(on: end, calendar: calendar)
    }

    /// From Never, the suggested end (`TaskRecurrenceRule.suggestedLastDay`), where the Custom… page starts too. An end
    /// already set stays.
    package mutating func startEnd(firstDay: Date, calendar: Calendar) {
        guard lastDay == nil else { return }
        lastDay = TaskRecurrenceRule.suggestedLastDay(firstDay: firstDay, calendar: calendar)
    }

    /// Moves the last day by `days`, never before the first day. Never stays Never.
    package mutating func stepEnd(days: Int, firstDay: Date, calendar: Calendar) {
        guard let lastDay else { return }
        self.lastDay = max(calendar.date(byAdding: .day, value: days, to: lastDay) ?? lastDay, calendar.startOfDay(for: firstDay))
    }
}
