import Foundation

/// The shared vocabulary used by normalization and complete-query parsing.
package enum TemporalWord: String, CaseIterable {
    case the, of
    case this, current, next, previous, last
    case today, tomorrow, yesterday
    case day, days, week, weeks, weekend, weekends, month, months, year, years
    case beginning, start, first, end, ending
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday
    case before, after, ago, from, now
    case morning, afternoon, evening, tonight, noon, midnight

    package var calendarWeekday: Int? {
        switch self {
        case .sunday: return 1
        case .monday: return 2
        case .tuesday: return 3
        case .wednesday: return 4
        case .thursday: return 5
        case .friday: return 6
        case .saturday: return 7
        default: return nil
        }
    }

    package static let spellable = Set(allCases).subtracting([.the, .of])
}

package enum TemporalLanguage {
    package static let matchingLocale = Locale(identifier: "en_US_POSIX")
    package static let spellingCode = "en_US"
}
