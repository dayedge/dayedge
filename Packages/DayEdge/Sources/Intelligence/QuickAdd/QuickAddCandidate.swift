import Foundation
import Domain
import TimeWhisper

package enum QuickAddCandidate: Equatable, Sendable {
    case task(TaskDraft)
    case event(EventDraft)

    init(_ candidate: Candidate, calendar: Calendar) throws {
        switch candidate.content {
        case .task(let task):
            let due: Date?
            switch task.due {
            case .onDate(let day): due = try day.date(calendar: calendar)
            case .atTime(let moment): due = moment.date
            case nil: due = nil
            }
            let hasTime: Bool
            if case .atTime = task.due { hasTime = true } else { hasTime = false }
            self = .task(TaskDraft(title: task.title, listID: task.listID, dueDate: due, hasDueTime: hasTime,
                                   priority: task.priority.taskPriority, recurrenceRule: task.recurrence?.taskRule,
                                   alert: task.reminder?.taskAlert))
        case .event(let event):
            let start: Date
            let end: Date
            let allDay: Bool
            switch event.time {
            case .timed(let first, let last):
                start = first.date; end = last.date; allDay = false
            case .allDay(let first, let last):
                start = try first.date(calendar: calendar); end = try last.date(calendar: calendar); allDay = true
            }
            self = .event(EventDraft(title: event.title, start: start, end: end, isAllDay: allDay,
                                     calendarIdentifier: event.calendarID, location: event.location,
                                     recurrenceRule: event.recurrence?.taskRule, alerts: event.reminders.map(\.eventAlert)))
        }
    }
}

private extension CivilDate {
    func date(calendar: Calendar) throws -> Date {
        // Civil dates are Gregorian even when the user's display calendar is different.
        var civil = Calendar(identifier: .gregorian)
        civil.timeZone = calendar.timeZone
        guard let date = civil.date(from: components) else { throw TimeWhisperError.backend("Invalid civil date") }
        return date
    }
}

private extension Priority {
    var taskPriority: TaskPriority {
        switch self {
        case .none: .none
        case .low: .low
        case .medium: .medium
        case .high: .high
        }
    }
}

private extension RecurrenceSpec {
    var taskRule: TaskRecurrenceRule {
        let frequency: TaskRecurrenceRule.Frequency
        switch self.frequency {
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        }
        return TaskRecurrenceRule(frequency: frequency, interval: interval,
                                  weekdays: weekdays.map { .init(weekday: $0.day.rawValue % 7 + 1, ordinal: $0.ordinal) },
                                  daysOfMonth: daysOfMonth)
    }
}

private extension ReminderSpec {
    var taskAlert: TaskAlert {
        switch self {
        case .before(let minutes): .relative(minutesBefore: minutes)
        case .at(let moment): .absolute(moment.date)
        }
    }
    var eventAlert: EventAlert {
        switch self {
        case .before(let minutes): .before(minutes: minutes)
        case .at(let moment): .at(moment.date)
        }
    }
}
