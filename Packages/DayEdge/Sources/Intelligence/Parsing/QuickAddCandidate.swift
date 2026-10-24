import Foundation
import Domain
import TimeWhisper

/// One thing TimeWhisper offers to create, as the app's own draft.
package enum QuickAddCandidate: Equatable, Sendable {
    case task(TaskDraft)
    case event(EventDraft)

    package var task: TaskDraft? { if case .task(let draft) = self { draft } else { nil } }
    package var event: EventDraft? { if case .event(let draft) = self { draft } else { nil } }

    /// The library's candidate in the app's types. Days the library gives without a time are midnight in `calendar`'s zone.
    init(_ candidate: Candidate, calendar: Calendar) throws {
        let zone = calendar.timeZone
        switch candidate.content {
        case .task(let task):
            let (due, hasTime): (Date?, Bool) = switch task.due {
            case .onDate(let day): (try day.date(in: zone), false)
            case .atTime(let moment): (moment.date, true)
            case nil: (nil, false)
            }
            self = .task(TaskDraft(title: task.title, listID: task.listID, dueDate: due, hasDueTime: hasTime,
                                   priority: task.priority.taskPriority, recurrenceRule: try task.recurrence?.taskRule(calendar: calendar),
                                   alert: task.reminder?.taskAlert))
        case .event(let event):
            let (start, end) = try event.time.span(in: zone)
            self = .event(EventDraft(title: event.title, start: start, end: end, isAllDay: event.time.isAllDay,
                                     calendarIdentifier: event.calendarID, location: event.location,
                                     recurrenceRule: try event.recurrence?.taskRule(calendar: calendar), alerts: event.reminders.map(\.eventAlert)))
        }
    }
}

private extension EventTime {
    var isAllDay: Bool { if case .allDay = self { true } else { false } }

    /// The start and the exclusive end. An all-day event's end is the midnight after its last day, as EventKit stores it.
    func span(in zone: TimeZone) throws -> (start: Date, end: Date) {
        switch self {
        case .timed(let start, let endExclusive): (start.date, endExclusive.date)
        case .allDay(let first, let endExclusive): (try first.date(in: zone), try endExclusive.date(in: zone))
        }
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
    /// The parser's repeat as the app stores it, ending with its last day (`until`).
    func taskRule(calendar: Calendar) throws -> TaskRecurrenceRule {
        let frequency: TaskRecurrenceRule.Frequency = switch self.frequency {
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        }
        return TaskRecurrenceRule(frequency: frequency, interval: interval,
                                  weekdays: weekdays.map { .init(weekday: $0.day.calendarWeekday, ordinal: $0.ordinal) },
                                  daysOfMonth: daysOfMonth)
            .ending(on: try until?.date(in: calendar.timeZone), calendar: calendar)
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
