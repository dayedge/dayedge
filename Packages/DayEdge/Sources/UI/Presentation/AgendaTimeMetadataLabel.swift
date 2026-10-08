import Foundation
import Domain

/// What an agenda row's time/status text should say for one event on one
/// displayed day — built once from (event, day), consumed by
/// `AgendaEventRowView`. Deliberately keeps the app's one existing time
/// grammar ("start – end") everywhere rather than switching to an arrow
/// notation for crossing events — a multi-day event's *endpoint* just
/// gains date context, e.g. "15:45 – Tomorrow 16:45".
package enum AgendaTimeMetadataLabel: Equatable {
    /// The plain range, as `TimeFormat` writes it ("11:00 – 11:45",
    /// "11:00–11:45am").
    case sameDay(range: String)
    /// "15:45" – "Tomorrow 16:45" — also covers the same-calendar-day
    /// event that happens to end exactly at midnight ("15:45 – Midnight"),
    /// since that reads the same way even though it never crosses into
    /// `.startsHereEndsLater`'s segment classification.
    case startsHereEndsLater(start: String, destination: String)
    case continuesThroughDay
    case endsHere(until: String)

    package static func build(event: AgendaEventModel, day: Date, calendar: Calendar,
                              format: TimeFormat = .twentyFourHour) -> AgendaTimeMetadataLabel? {
        guard !event.isAllDay, let start = event.startDate, let end = event.endDate,
              let segment = MultiDaySegment.classify(start: start, end: end, day: day, calendar: calendar)
        else { return nil }

        switch segment {
        case .sameDay:
            guard MultiDaySegment.endsAtMidnightBoundary(start: start, end: end, calendar: calendar) else {
                return .sameDay(range: event.rangeText(format, calendar: calendar) ?? "")
            }
            return .startsHereEndsLater(start: event.startText(format, calendar: calendar) ?? "", destination: L10n.tr("agendatimemetadatalabel.midnight", "Midnight"))
        case .startsHereEndsLater:
            let dayReference = RelativeDayLabelFormatter.dayReference(for: end, relativeTo: day, calendar: calendar)
            let endTime = event.endText(format, calendar: calendar) ?? ""
            return .startsHereEndsLater(start: event.startText(format, calendar: calendar) ?? "",
                                        destination: "\(dayReference) \(endTime)")
        case .continuesThroughDay:
            return .continuesThroughDay
        case .endsHere:
            return .endsHere(until: event.endText(format, calendar: calendar) ?? "")
        }
    }

    /// The row's rendered text — a single string, since (per spec) a
    /// multi-day segment must not read any louder than an ordinary
    /// "11:00 – 11:45" row: same font, weight, and color throughout.
    package var displayText: String {
        switch self {
        case .sameDay(let range): range
        case .startsHereEndsLater(let start, let destination): "\(start) – \(destination)"
        case .continuesThroughDay: L10n.tr("agendatimemetadatalabel.continues", "Continues")
        case .endsHere(let until): L10n.tr("agendatimemetadatalabel.continues.57c707", "Continues – \(String(describing: until))")
        }
    }
}
