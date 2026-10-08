import Foundation

/// An event alert, as Calendar offers them: an offset from the start
/// (negative minutes = after it — an all-day event's "on the day, 9:00" is
/// 540 minutes after its midnight start), or a fixed moment.
package enum EventAlert: Hashable, Sendable {
    /// Minutes before the start; negative is after.
    case before(minutes: Int)
    case at(Date)

    /// Calendar's own choices.
    package static func presets(isAllDay: Bool) -> [EventAlert] {
        isAllDay
            ? [-540, 900, 2340, 9540].map { .before(minutes: $0) } // the day, 1 day, 2 days, 1 week — at 9:00
            : [0, 5, 10, 15, 30, 60, 120, 1440, 2880, 10080].map { .before(minutes: $0) }
    }

    package func title(isAllDay: Bool, format: TimeFormat = .twentyFourHour, dates: DatePresentationFormatter = .current) -> String {
        switch self {
        case .at(let date):
            return dates.format(date, .compact, weekday: .abbreviated) + " " + format.time(date)
        case .before(let minutes) where isAllDay:
            // Offsets from midnight: whole days before, at a time of day.
            let dayMinutes = 24 * 60
            let daysBefore = Int((Double(minutes) / Double(dayMinutes)).rounded(.up))
            let time = daysBefore * dayMinutes - minutes
            let clock = format.time(hour: time / 60, minute: time % 60)
            switch daysBefore {
            case 0: return L10n.tr("eventalert.on.day.of.event", "On day of event (\(clock))", locale: dates.displayLocale)
            case 1: return L10n.tr("eventalert.1.day.before", "1 day before (\(clock))", locale: dates.displayLocale)
            case 7: return L10n.tr("eventalert.1.week.before", "1 week before (\(clock))", locale: dates.displayLocale)
            default: return L10n.tr("eventalert.days.before", "\(daysBefore) days before (\(clock))", locale: dates.displayLocale)
            }
        case .before(let minutes):
            if minutes == 0 {
                return L10n.tr("eventalert.at.time.of.event", "At time of event", locale: dates.displayLocale)
            }
            return Self.offsetTitle(minutes, locale: dates.displayLocale)
        }
    }

    /// Complete phrases let each language choose its word order and plural forms.
    private static func offsetTitle(_ minutes: Int, locale: Locale) -> String {
        let amount = abs(minutes)
        let before = minutes > 0
        if amount % 10080 == 0 {
            let count = amount / 10080
            return before
                ? L10n.tr("eventalert.offset.weeks.before", "\(count) weeks before", locale: locale)
                : L10n.tr("eventalert.offset.weeks.after", "\(count) weeks after", locale: locale)
        }
        if amount % 1440 == 0 {
            let count = amount / 1440
            return before
                ? L10n.tr("eventalert.offset.days.before", "\(count) days before", locale: locale)
                : L10n.tr("eventalert.offset.days.after", "\(count) days after", locale: locale)
        }
        if amount % 60 == 0 {
            let count = amount / 60
            return before
                ? L10n.tr("eventalert.offset.hours.before", "\(count) hours before", locale: locale)
                : L10n.tr("eventalert.offset.hours.after", "\(count) hours after", locale: locale)
        }
        let count = amount
        return before
            ? L10n.tr("eventalert.offset.minutes.before", "\(count) minutes before", locale: locale)
            : L10n.tr("eventalert.offset.minutes.after", "\(count) minutes after", locale: locale)
    }
}
