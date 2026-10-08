import Foundation
import Domain

/// How an assistant message is laid out: prose; runs of referenced events
/// and tasks grouped by the day they belong to, under one date header; and
/// runs of referenced days, shown as native dates. Date belongs to the
/// group; time to the row.
///
/// Deterministic, from the references themselves: the model only names
/// objects and days, the renderer decides how they look.
package enum ChatContentBlock: Equatable {
    case prose(String)
    /// Events and tasks of one day, under that day's header.
    case objects(ChatDayReference, [ChatContentPart])
    /// Days on their own (holidays, free days, a span).
    case dates([ChatDayReference])

    package static func blocks(_ parts: [ChatContentPart], calendar: Calendar) -> [ChatContentBlock] {
        var blocks: [ChatContentBlock] = []
        for part in parts {
            switch part {
            case .text(let text):
                blocks.append(.prose(text))
            case .day(let reference):
                if case .dates(let run)? = blocks.last {
                    blocks[blocks.count - 1] = .dates(run + [reference])
                } else {
                    blocks.append(.dates([reference]))
                }
            case .event, .task:
                guard let objectDay = part.day.map({ calendar.startOfDay(for: $0) }) else { continue }
                switch blocks.last {
                case .objects(let header, let run)? where calendar.startOfDay(for: header.day) == objectDay:
                    // Same day as the run just before it: one group.
                    blocks[blocks.count - 1] = .objects(header, run + [part])
                case .dates(let days)? where days.count == 1 && calendar.startOfDay(for: days[0].day) == objectDay:
                    // "[[D1]]" then that day's events: the date becomes the
                    // group's header rather than showing twice.
                    blocks[blocks.count - 1] = .objects(days[0], [part])
                default:
                    blocks.append(.objects(ChatDayReference(day: objectDay), [part]))
                }
            }
        }
        return blocks
    }
}

/// How a run of days is presented — a fixed rule, never the model's choice.
package enum ChatDatePresentation: Equatable {
    /// One day: a single date reference.
    case single
    /// A few days (2–7): one strip of day columns.
    case strip
    /// More: grouped by month, each month a compact run of strips.
    case byMonth

    package static let stripLimit = 7

    package static func choose(count: Int) -> ChatDatePresentation {
        switch count {
        case ..<2: return .single
        case ...stripLimit: return .strip
        default: return .byMonth
        }
    }
}

extension ChatContentPart {
    /// The day a referenced object belongs to; nil for prose.
    package var day: Date? {
        switch self {
        case .event(let event): return event.day
        case .task(let task): return task.day
        case .day(let day): return day.day
        case .text: return nil
        }
    }
}

/// The words of a native date, from the app's date formatter: "23", "Wed",
/// "Dec", "Wed Dec", "December 2027", and a full spoken form for VoiceOver.
package enum ChatDayText {
    package static func dayNumber(_ day: Date, calendar: Calendar, dates: DatePresentationFormatter = .current) -> String {
        dates.with(calendar).day(day)
    }

    package static func weekday(_ day: Date, calendar: Calendar, dates: DatePresentationFormatter = .current) -> String {
        dates.with(calendar).weekday(day, .abbreviated)
    }

    package static func month(_ day: Date, calendar: Calendar, dates: DatePresentationFormatter = .current) -> String {
        dates.with(calendar).month(day, abbreviated: true)
    }

    /// Beside a large day number: "Wed Dec" (the year only outside the
    /// current one).
    package static func weekdayAndMonth(_ day: Date, now: Date, calendar: Calendar, dates: DatePresentationFormatter = .current) -> String {
        let dates = dates.with(calendar)
        let text = "\(dates.weekday(day, .abbreviated)) \(dates.month(day, abbreviated: true))"
        return isThisYear(day, now: now, calendar: calendar) ? text : "\(text) \(dates.year(day))"
    }

    /// A month heading: "December", or "December 2027" outside this year.
    package static func monthTitle(_ day: Date, now: Date, calendar: Calendar, dates: DatePresentationFormatter = .current) -> String {
        let dates = dates.with(calendar)
        return isThisYear(day, now: now, calendar: calendar) ? dates.month(day, abbreviated: false) : dates.monthYear(day)
    }

    /// "Friday 25 December 2026, Christmas Day".
    package static func spoken(_ reference: ChatDayReference, calendar: Calendar, dates: DatePresentationFormatter = .current) -> String {
        let date = dates.with(calendar).format(reference.day, .standard)
        return reference.label.map { "\(date), \($0)" } ?? date
    }

    package static func isThisYear(_ day: Date, now: Date, calendar: Calendar) -> Bool {
        calendar.component(.year, from: day) == calendar.component(.year, from: now)
    }
}

/// "Today · Tue 29 Sep", "Tomorrow · Wed 30 Sep", "Fri 2 Oct",
/// "Mon 12 Oct 2027" — a relative word only where there is one, always the
/// concrete date (chat history is reread later), the year only outside the
/// current one.
package enum ChatDayLabel {
    package static func text(for day: Date, now: Date, calendar: Calendar, dates: DatePresentationFormatter = .current) -> String {
        let absolute = dates.with(calendar).format(day, .compact, weekday: .abbreviated, relativeTo: now)
        guard let relative = relativeWord(for: day, now: now, calendar: calendar, dates: dates) else { return absolute }
        return "\(relative) · \(absolute)"
    }

    /// "Today", "Tomorrow", "Yesterday" — nil for any other day.
    package static func relativeWord(for day: Date, now: Date, calendar: Calendar, dates: DatePresentationFormatter = .current) -> String? {
        dates.with(calendar).relativeDay(day, relativeTo: now)
    }
}
