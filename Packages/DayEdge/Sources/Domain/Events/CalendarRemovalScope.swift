import Foundation

/// Wording for removing a cancelled event, tied to the EventKit span —
/// shown on a destructive `DecisionCard`.
package enum CalendarRemovalScope {
    case occurrence
    case event
    case futureOccurrences
    case series

    package var title: String {
        switch self {
        case .occurrence: L10n.tr("calendarremovalscope.remove.this.occurrence", "Remove this occurrence?")
        case .event: L10n.tr("calendarremovalscope.remove.this.event", "Remove this event?")
        case .futureOccurrences: L10n.tr("calendarremovalscope.remove.this.and.future.occurrences", "Remove this and future occurrences?")
        case .series: L10n.tr("calendarremovalscope.remove.this.series", "Remove this series?")
        }
    }

    package var message: String {
        switch self {
        case .occurrence: L10n.tr("calendarremovalscope.other.events.in.this.series.2482f8", "Other events in this series won’t be affected.")
        case .event: L10n.tr("calendarremovalscope.this.removes.it.from.your.calendar", "This removes it from your calendar.")
        case .futureOccurrences: L10n.tr("calendarremovalscope.earlier.events.in.this.fe74d7", "Earlier events in this series won’t be affected.")
        case .series: L10n.tr("calendarremovalscope.all.occurrences.in.this.5bf1bd", "All occurrences in this series will be removed.")
        }
    }
}
