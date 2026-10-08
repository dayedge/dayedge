import Foundation
import Domain

/// What an assistant message is made of: prose, the real the app objects
/// it points at, and the days it's about. The model only says *which*; how
/// they look is the app's (`ChatObjectReferenceRow`, `ChatDateViews`).
package enum ChatContentPart: Equatable, Sendable {
    case text(String)
    case event(ChatEventReference)
    case task(ChatTaskReference)
    case day(ChatDayReference)
}

/// A calendar day the conversation is about — a holiday, a free day, a
/// day of a span. Shown as a native date, never as Markdown.
package struct ChatDayReference: Equatable, Sendable {
    /// Start of the day.
    package let day: Date
    /// What the day is, when it's something ("Christmas Day").
    package var label: String?
    package var isHoliday = false
    package var isWeekend = false

    /// The month grid's own precedence: a weekend is a weekend; a holiday
    /// is marked only on a work day.
    package var tint: DayTint {
        if isWeekend { return .weekend }
        return isHoliday ? .holiday : .plain
    }

    package enum DayTint: Equatable, Sendable {
        case plain, weekend, holiday
    }
}

/// A calendar event occurrence, by its stable id.
package struct ChatEventReference: Equatable, Sendable {
    /// `AgendaEventModel.id` — already unique per occurrence.
    package let id: String
    /// The day it was shown on, to find it again.
    package let day: Date
    /// What it looked like when the tool returned it; shown only if the
    /// event can't be found any more.
    package let snapshot: ChatObjectSnapshot
}

/// A task (reminder), by its stable id.
package struct ChatTaskReference: Equatable, Sendable {
    /// `TaskItem.id`.
    package let id: String
    /// The day this occurrence belongs to (a repeating task has several);
    /// the task's own day, or today, for a task shown without one.
    package let day: Date
    package let snapshot: ChatObjectSnapshot
}

package struct ChatObjectSnapshot: Equatable, Sendable {
    package let title: String
    /// "10:30–10:55", "due 14:00" — a short, safe display hint.
    package var detail: String?
}

/// Either kind of reference, as the registry stores it.
package enum ChatObjectReference: Equatable, Sendable {
    case event(ChatEventReference)
    case task(ChatTaskReference)
    case day(ChatDayReference)

    /// How it reads inside a sentence.
    package var title: String {
        switch self {
        case .event(let event): return event.snapshot.title
        case .task(let task): return task.snapshot.title
        case .day(let day):
            let date = DatePresentationFormatter.current.format(day.day, .compact, weekday: .abbreviated)
            return day.label.map { "\($0) (\(date))" } ?? date
        }
    }

    package var part: ChatContentPart {
        switch self {
        case .event(let event): return .event(event)
        case .task(let task): return .task(task)
        case .day(let day): return .day(day)
        }
    }
}
