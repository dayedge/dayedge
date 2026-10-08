import Foundation

/// "Tomorrow" / "Yesterday" / short weekday / compact date — the
/// destination-day wording shared by the Agenda's and Day view's
/// multi-day time labels, so the two don't independently drift on what
/// counts as "near enough" to abbreviate. Symmetric: works whether `date`
/// falls after or before `referenceDay`, since it backs both a forward
/// endpoint ("15:45 – Tomorrow 16:45") and a backward one ("Since
/// Yesterday – 16:45").
package enum RelativeDayLabelFormatter {
    /// No time component — e.g. "Tomorrow", "Yesterday", "Fri", "3 Oct"
    /// ("Oct 3" in the US), "2 Jan 2027".
    package static func dayReference(for date: Date, relativeTo referenceDay: Date, calendar: Calendar,
                                     dates: DatePresentationFormatter = .current) -> String {
        let dates = dates.with(calendar)
        let referenceStart = calendar.startOfDay(for: referenceDay)
        let dateStart = calendar.startOfDay(for: date)
        let dayCount = calendar.dateComponents([.day], from: referenceStart, to: dateStart).day ?? 0

        if abs(dayCount) == 1, let word = dates.relativeDay(date, relativeTo: referenceDay) { return word }

        let referenceYear = calendar.component(.year, from: referenceStart)
        let dateYear = calendar.component(.year, from: dateStart)
        // A year crossing always gets an explicit year, and a month
        // crossing always gets an explicit date — a bare weekday
        // ("Fri") is only unambiguous within the same month.
        if dateYear != referenceYear {
            return dates.format(date, .short, year: .always)
        }
        let referenceMonth = calendar.component(.month, from: referenceStart)
        let dateMonth = calendar.component(.month, from: dateStart)
        if dateMonth != referenceMonth {
            return dates.format(date, .short, relativeTo: referenceDay)
        }
        if abs(dayCount) <= 6 {
            return dates.weekday(date, .abbreviated)
        }
        return dates.format(date, .short, relativeTo: referenceDay)
    }

}
