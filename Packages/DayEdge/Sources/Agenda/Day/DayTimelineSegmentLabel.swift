import Foundation
import Domain
import UI

/// The Day view's counterpart to `AgendaTimeMetadataLabel` — same "start –
/// end" grammar, just with a little more date context on the final-day
/// wording since the Day view has room for it and is routinely navigated
/// far from "now" (unlike the Agenda's near-term scrolling, where a plain
/// "Continues – 16:45" reads clearly enough on its own).
package enum DayTimelineSegmentLabel: Equatable {
    /// Unchanged from today's plain rendering.
    case sameDay
    /// "Tomorrow 16:45" / "Fri 16:45" / "3 Oct 16:45" / "2 Jan 2027 16:45"
    /// / "Midnight" — rendered as "\(event.startTime) – \(destination)".
    case startsHereEndsLater(destination: String)
    case continuesThroughDay
    /// "Yesterday" or "Tue 22 Sep" — rendered as "Since \(since) – \(until)".
    case endsHere(since: String, until: String)

    package static func build(event: AgendaEventModel, day: Date, calendar: Calendar,
                              format: TimeFormat = .twentyFourHour) -> DayTimelineSegmentLabel? {
        guard !event.isAllDay, let start = event.startDate, let end = event.endDate,
              let segment = MultiDaySegment.classify(start: start, end: end, day: day, calendar: calendar)
        else { return nil }

        switch segment {
        case .sameDay:
            guard MultiDaySegment.endsAtMidnightBoundary(start: start, end: end, calendar: calendar) else {
                return .sameDay
            }
            return .startsHereEndsLater(destination: L10n.tr("daytimelinesegmentlabel.midnight", "Midnight"))
        case .startsHereEndsLater:
            let dayReference = RelativeDayLabelFormatter.dayReference(for: end, relativeTo: day, calendar: calendar)
            return .startsHereEndsLater(destination: "\(dayReference) \(event.endText(format, calendar: calendar) ?? "")")
        case .continuesThroughDay:
            return .continuesThroughDay
        case .endsHere:
            let dayCount = calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: day), to: calendar.startOfDay(for: start)
            ).day ?? 0
            let since = dayCount == -1 ? L10n.tr("daytimelinesegmentlabel.yesterday", "Yesterday") : fullDayLabel(for: start, relativeTo: day, calendar: calendar)
            return .endsHere(since: since, until: event.endText(format, calendar: calendar) ?? "")
        }
    }

    /// "Tue 22 Sep" — or, when `date`'s year differs from `referenceDay`'s,
    /// "Tue 22 Sep 2026". Unlike `RelativeDayLabelFormatter`'s compact
    /// forward endpoint, the "Since" wording always pairs weekday + date
    /// (never a bare weekday), since it's describing an origin day that
    /// could be arbitrarily far in the past.
    private static func fullDayLabel(for date: Date, relativeTo referenceDay: Date, calendar: Calendar) -> String {
        let dateYear = calendar.component(.year, from: date)
        let referenceYear = calendar.component(.year, from: referenceDay)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = dateYear == referenceYear ? "EEE d MMM" : "EEE d MMM yyyy"
        return formatter.string(from: date)
    }
}
