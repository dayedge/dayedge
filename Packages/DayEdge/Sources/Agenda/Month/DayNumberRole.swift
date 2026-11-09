import SwiftUI
import Domain
import UI

/// What a date's number says about its day, for both month grids — the
/// compact calendar and the Command Window's: one rule, two geometries.
/// Today first, then a day outside the month shown, a weekend, a holiday
/// on a working day (`WorkdayStore.isMarkedHoliday`: weekend holidays keep
/// the weekend's look), else a regular day. Selection is each grid's own.
package enum DayNumberRole: Equatable {
    case today
    case outsideMonth
    case weekend
    case holiday
    case regular

    package init(isToday: Bool, isCurrentMonth: Bool, isWeekend: Bool, isMarkedHoliday: Bool) {
        if isToday {
            self = .today
        } else if !isCurrentMonth {
            self = .outsideMonth
        } else if isWeekend {
            self = .weekend
        } else if isMarkedHoliday {
            self = .holiday
        } else {
            self = .regular
        }
    }

    package func color(in theme: ThemePalette) -> Color {
        switch self {
        case .today: theme.todayText
        case .outsideMonth: theme.dimmedText
        case .weekend: theme.weekendDayTint
        case .holiday: theme.holidayTint
        case .regular: theme.primaryText
        }
    }
}
