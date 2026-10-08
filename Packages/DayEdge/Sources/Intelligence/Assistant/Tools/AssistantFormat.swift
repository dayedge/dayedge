import Foundation
import Domain
import UI

/// How tool answers read: compact, one line per item, absolute dates, in
/// English (the model's working language, not the user's locale).
package enum AssistantFormat {
    package static func dayTitle(_ date: Date, calendar: Calendar) -> String {
        formatter("EEEE d MMMM yyyy", calendar: calendar).string(from: date)
    }

    package static func shortDay(_ date: Date, calendar: Calendar) -> String {
        formatter("EEE d MMM", calendar: calendar).string(from: date)
    }

    /// "21 Sep 2026" — creation dates can be years back.
    package static func date(_ date: Date, calendar: Calendar) -> String {
        formatter("d MMM yyyy", calendar: calendar).string(from: date)
    }

    /// "21 Sep 2026 14:05".
    package static func stamp(_ date: Date, calendar: Calendar) -> String {
        formatter("d MMM yyyy HH:mm", calendar: calendar).string(from: date)
    }

    package static func time(_ date: Date, calendar: Calendar) -> String {
        formatter("HH:mm", calendar: calendar).string(from: date)
    }

    /// "Monday 5 October 2026" or "Monday 5 October 2026 – Sunday 11 October 2026".
    package static func period(_ interval: DateInterval, calendar: Calendar) -> String {
        let first = calendar.startOfDay(for: interval.start)
        let last = calendar.startOfDay(for: interval.end.addingTimeInterval(-1))
        return first == last
            ? dayTitle(first, calendar: calendar)
            : "\(dayTitle(first, calendar: calendar)) – \(dayTitle(last, calendar: calendar))"
    }

    /// "09:00–09:30 Standup · Work · Room 4 · video call · tentative".
    package static func event(_ event: AgendaEventModel) -> String {
        var parts = [event.isAllDay ? "all day \(event.title)" : "\(timeRange(event)) \(event.title)"]
        if !event.calendarName.isEmpty { parts.append(event.calendarName) }
        if let place = event.subtitle, !place.isEmpty { parts.append(place) }
        if event.videoURL != nil { parts.append("video call") }
        switch event.status {
        case .tentative: parts.append("tentative")
        case .cancelled: parts.append("cancelled or declined")
        default: break
        }
        return parts.joined(separator: " · ")
    }

    /// "Send invoice · due Fri 2 Oct 10:00 · Work · high priority · repeats".
    package static func task(_ task: TaskItem, list: String?, now: Date, calendar: Calendar, showsDay: Bool = true) -> String {
        var parts = [task.title]
        if let due = task.dueDate {
            var text = "due"
            if showsDay { text += " \(shortDay(due, calendar: calendar))" }
            if task.hasDueTime { text += " \(time(due, calendar: calendar))" }
            if text != "due" { parts.append(text) }
            if !task.isCompleted, TaskBuckets.isOverdue(task, now: now, calendar: calendar) { parts.append("overdue") }
        }
        if let list { parts.append(list) }
        if task.priority != .none { parts.append("\(task.priority.assistantValue) priority") }
        if task.isRecurring { parts.append("repeats") }
        if task.isCompleted { parts.append("done") }
        return parts.joined(separator: " · ")
    }

    /// Closes every answer that lists events or tasks. Small models follow
    /// what's closest to their reply far better than the system prompt.
    package static let referenceHint = "To show any of these to the user, write its reference (like [[E1]]) alone on its own line; "
        + "the app displays it. Don't retype its time or title. Days ([[D1]]) can be shown the same way."

    /// At most `max` lines; the rest counted, not dropped silently.
    package static func capped(_ lines: [String], max: Int) -> String {
        var listing = AssistantListing(maxLines: max)
        for line in lines { listing.append(line) }
        return listing.text
    }

    package static func timeRange(_ event: AgendaEventModel) -> String {
        switch (event.startTime, event.endTime) {
        case let (start?, end?): return "\(start)–\(end)"
        case let (start?, nil): return start
        case let (nil, end?): return "until \(end)"
        case (nil, nil): return ""
        }
    }

    private static func formatter(_ format: String, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }
}
