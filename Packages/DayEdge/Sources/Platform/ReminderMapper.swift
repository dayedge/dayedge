import EventKit
import Foundation
import Domain

/// `EKReminder` ⇄ `TaskItem`. Stateless. Reads produce plain values; writes
/// touch only the field a `TaskChange` is about, so anything the app can't
/// express (a custom repeat rule, a location alert) survives an edit.
package enum ReminderMapper {
    // MARK: Reading

    package static func taskItem(from reminder: EKReminder, calendar: Calendar) -> TaskItem {
        let due = dueDate(from: reminder.dueDateComponents, calendar: calendar)
        return TaskItem(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            notes: reminder.notes,
            url: reminder.url,
            listID: reminder.calendar?.calendarIdentifier ?? "",
            dueDate: due.date,
            hasDueTime: due.hasTime,
            priority: priority(fromEventKit: reminder.priority),
            isCompleted: reminder.isCompleted,
            completionDate: reminder.completionDate,
            recurrence: recurrence(from: reminder.recurrenceRules, due: due.date, calendar: calendar),
            recurrenceRule: reminder.recurrenceRules?.first.map(rule(from:)),
            alert: alert(from: reminder.alarms),
            creationDate: reminder.creationDate,
            lastModifiedDate: reminder.lastModifiedDate
        )
    }

    // MARK: Priority

    /// EventKit uses 1–9 (1 highest, 0 none); Reminders.app itself only ever
    /// writes 1, 5 and 9.
    package static func priority(fromEventKit value: Int) -> TaskPriority {
        switch value {
        case 1...4: return .high
        case 5: return .medium
        case 6...9: return .low
        default: return .none
        }
    }

    package static func eventKitPriority(_ priority: TaskPriority) -> Int {
        switch priority {
        case .none: return 0
        case .high: return 1
        case .medium: return 5
        case .low: return 9
        }
    }

    // MARK: Due date

    /// A date-only reminder has no hour component; timed ones do.
    package static func dueDate(from components: DateComponents?, calendar: Calendar) -> (date: Date?, hasTime: Bool) {
        guard let components, components.year != nil || components.month != nil || components.day != nil else {
            return (nil, false)
        }
        var dueCalendar = components.calendar ?? calendar
        // EventKit can attach its own calendar to floating date components.
        // Their day belongs to the caller's current zone, not that metadata's zone.
        dueCalendar.timeZone = components.timeZone ?? calendar.timeZone
        guard let date = dueCalendar.date(from: components) else { return (nil, false) }
        return (date, components.hour != nil)
    }

    /// Date-only reminders are written "floating" (no time zone) so they stay
    /// on the same calendar day when the user travels; timed ones are pinned
    /// to the current zone.
    package static func dueComponents(for date: Date, hasTime: Bool, calendar: Calendar) -> DateComponents {
        if hasTime {
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            components.timeZone = calendar.timeZone
            return components
        }
        return calendar.dateComponents([.year, .month, .day], from: date)
    }

    // MARK: Alerts

    /// The time-based alarm the app shows; location alarms are not its
    /// business and are left alone.
    private static func isTimeAlarm(_ alarm: EKAlarm) -> Bool { alarm.structuredLocation == nil }

    package static func alert(from alarms: [EKAlarm]?) -> TaskAlert? {
        guard let alarm = alarms?.first(where: isTimeAlarm) else { return nil }
        if let date = alarm.absoluteDate { return .absolute(date) }
        guard alarm.relativeOffset <= 0 else { return nil }
        return .relative(minutesBefore: Int((-alarm.relativeOffset / 60).rounded()))
    }

    package static func alarm(for alert: TaskAlert) -> EKAlarm {
        switch alert {
        case .relative(let minutes): return EKAlarm(relativeOffset: -TimeInterval(minutes) * 60)
        case .absolute(let date): return EKAlarm(absoluteDate: date)
        }
    }

    /// Replaces the time alarm with `alert`, keeping any location alarms.
    package static func setAlert(_ alert: TaskAlert?, on reminder: EKReminder) {
        for alarm in reminder.alarms ?? [] where isTimeAlarm(alarm) { reminder.removeAlarm(alarm) }
        if let alert { reminder.addAlarm(alarm(for: alert)) }
    }
}

extension Optional where Wrapped: Collection {
    var isNilOrEmpty: Bool { self?.isEmpty ?? true }
}
