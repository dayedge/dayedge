import Foundation
import Domain

/// The editable Quick Add fields, prefilled from the parsed draft (Tab).
/// Only what creation needs — no notes, URL or other Task Details.
package struct QuickAddEdit: Equatable {
    package var title: String
    /// nil = the source's default list.
    package var listID: String?
    package var day: Date?
    package var hasTime: Bool
    /// Only the hour and minute are used.
    package var time: Date
    package var priority: TaskPriority
    /// Repeat and End Repeat; they only apply with a date.
    package var repeating: RepeatEdit
    package var alert: TaskAlert?

    package init(draft: TaskDraft, calendar: Calendar, referenceDate: Date) {
        title = draft.title
        listID = draft.listID
        day = draft.dueDate.map { calendar.startOfDay(for: $0) }
        hasTime = draft.hasDueTime
        let base = day ?? calendar.startOfDay(for: referenceDate)
        time = draft.hasDueTime ? (draft.dueDate ?? base)
            : (calendar.date(bySettingHour: 9, minute: 0, second: 0, of: base) ?? base)
        priority = draft.priority
        repeating = RepeatEdit(rule: draft.recurrenceRule, calendar: calendar)
        alert = draft.alert
    }

    package var canCreate: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    package func taskDraft(calendar: Calendar) -> TaskDraft {
        var due = day.map { calendar.startOfDay(for: $0) }
        if let day, hasTime {
            let parts = calendar.dateComponents([.hour, .minute], from: time)
            due = calendar.isDate(time, inSameDayAs: day) ? time
                : calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: day)
        }
        return TaskDraft(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines), listID: listID,
            dueDate: due, hasDueTime: due != nil && hasTime, priority: priority,
            recurrenceRule: due.flatMap { repeating.rule(firstDay: $0, calendar: calendar) },
            // A time-relative alert needs a due time, as in `TaskItem`.
            alert: alert.flatMap { $0.isRelative && !(due != nil && hasTime) ? nil : $0 }
        )
    }
}

/// Create Event, expanded in place (Tab): the fields an event needs,
/// prefilled from the parsed draft.
package struct EventQuickAddEdit: Equatable {
    package var title: String
    /// nil = the default calendar for new events.
    package var calendarID: String?
    /// When it starts and ends; the rules for changing them live there.
    package var timing: EventTiming
    package var location: String
    package var repeating: RepeatEdit
    /// Parsed alerts. Quick Add edits the first (`firstAlert`); any others are kept as they are.
    package var alerts: [EventAlert]

    package init(draft event: EventDraft, calendar: Calendar) {
        title = event.title
        calendarID = event.calendarIdentifier
        timing = EventTiming(start: event.start, end: event.end, isAllDay: event.isAllDay, calendar: calendar)
        location = event.location ?? ""
        repeating = RepeatEdit(rule: event.recurrenceRule, calendar: calendar)
        alerts = event.alerts
    }

    /// The alert Alert shows and changes: the first; nil removes it, keeping the rest.
    package var firstAlert: EventAlert? {
        get { alerts.first }
        set { alerts = alerts.replacingFirst(with: newValue) }
    }

    /// The timing is always valid, so only a title is needed.
    package var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    package func eventDraft(calendar: Calendar) -> EventDraft {
        let place = location.trimmingCharacters(in: .whitespacesAndNewlines)
        return EventDraft(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            start: timing.start, end: timing.end, isAllDay: timing.isAllDay,
            calendarIdentifier: calendarID, location: place.isEmpty ? nil : place,
            recurrenceRule: repeating.rule(firstDay: timing.firstDay, calendar: calendar), alerts: alerts
        )
    }
}
