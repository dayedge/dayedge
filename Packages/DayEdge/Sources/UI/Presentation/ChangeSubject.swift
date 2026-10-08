import SwiftUI
import Domain

/// What a proposed change is about, drawn the way the app draws it.
package struct ChangeSubject: Equatable, Sendable {
    package enum Marker: Equatable, Sendable {
        /// A task's ring, in its list's colour.
        case ring(Color)
        /// An event's dot, in its calendar's colour.
        case dot(Color)
    }

    package let marker: Marker
    package let title: String
    /// "Tomorrow 15:00 · Reminders".
    package var detail: String?

    package init(marker: Marker, title: String, detail: String? = nil) {
        self.marker = marker
        self.title = title
        self.detail = detail
    }
}

extension ChangeSubject {
    /// An event as a decision card or receipt names it: dot, title, when and calendar.
    package static func event(_ event: AgendaEventModel, now: Date, calendar: Calendar,
                              format: TimeFormat = .twentyFourHour) -> ChangeSubject {
        let when = event.startDate.map { start in
            ChangeText.span(start: start, end: event.endDate ?? start, isAllDay: event.isAllDay, now: now, calendar: calendar, format: format)
        }
        return ChangeSubject(marker: .dot(event.color), title: event.title,
                             detail: ChangeText.joined(when, event.calendarName.isEmpty ? nil : event.calendarName))
    }
}

/// How decision cards and receipts write when something is: "Today 15:00",
/// "Tomorrow", "Fri 2 Oct 09:30".
package enum ChangeText {
    /// "Today 15:00", "Tomorrow", "Fri 2 Oct 09:30" — how cards and
    /// receipts say when.
    package static func when(_ date: Date, hasTime: Bool, now: Date, calendar: Calendar,
                             format: TimeFormat = .twentyFourHour, locale: Locale = AppLocalization.displayLocale) -> String {
        let day: String
        if calendar.isDate(date, inSameDayAs: now) {
            day = L10n.tr("changesubject.today", "Today", locale: locale)
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            day = L10n.tr("changesubject.tomorrow", "Tomorrow", locale: locale)
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            day = L10n.tr("changesubject.yesterday", "Yesterday", locale: locale)
        } else {
            day = shortDay(date, calendar: calendar, locale: locale)
        }
        return hasTime ? "\(day) \(format.time(date, calendar: calendar))" : day
    }

    /// "Fri 2 Oct 15:00–16:00" ("3:00–4:00pm"), "Fri 2 Oct, all day". Shown
    /// on approval cards and receipts, so in the user's time format.
    package static func span(start: Date, end: Date, isAllDay: Bool, now: Date, calendar: Calendar,
                             format: TimeFormat = .twentyFourHour, locale: Locale = AppLocalization.displayLocale) -> String {
        let day = when(start, hasTime: false, now: now, calendar: calendar, locale: locale)
        if isAllDay { return L10n.tr("changesubject.all.day", "\(String(describing: day)), all day", locale: locale) }
        return "\(day) " + format.range(start, end, calendar: calendar).replacingOccurrences(of: " – ", with: "–")
    }

    package static func joined(_ parts: String?...) -> String? { joined(parts) }

    package static func joined(_ parts: [String?]) -> String? {
        let present = parts.compactMap { $0 }.filter { !$0.isEmpty }
        return present.isEmpty ? nil : present.joined(separator: " · ")
    }

    /// "Fri 2 Oct".
    private static func shortDay(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        if locale.language.languageCode?.identifier != "en" {
            return DatePresentationFormatter(displayLocale: locale, calendar: calendar)
                .format(date, .compact, weekday: .abbreviated, relativeTo: date)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date)
    }
}
