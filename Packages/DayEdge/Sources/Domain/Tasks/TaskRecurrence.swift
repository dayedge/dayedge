import Foundation

/// How a reminder repeats. `.custom` carries a rule the app can't express
/// (it is shown as its summary and left untouched unless the user picks
/// another value), so editing never silently destroys a complex rule.
package enum TaskRecurrence: Hashable, Sendable {
    case never
    case daily
    case weekdays
    case weekly
    case biweekly
    case monthly
    case yearly
    case custom(String)

    /// What the Repeat menu offers.
    package static let standard: [TaskRecurrence] = [.never, .daily, .weekdays, .weekly, .biweekly, .monthly, .yearly]

    package var isRepeating: Bool { self != .never }

    /// A rule the app can show but not compute.
    package var isCustom: Bool {
        if case .custom = self { return true }
        return false
    }

    package var title: String {
        switch self {
        case .never: return L10n.tr("taskrecurrence.never", "Never")
        case .daily: return L10n.tr("taskrecurrence.daily", "Daily")
        case .weekdays: return L10n.tr("taskrecurrence.weekdays", "Weekdays")
        case .weekly: return L10n.tr("taskrecurrence.weekly", "Weekly")
        case .biweekly: return L10n.tr("taskrecurrence.every.2.weeks", "Every 2 Weeks")
        case .monthly: return L10n.tr("taskrecurrence.monthly", "Monthly")
        case .yearly: return L10n.tr("taskrecurrence.yearly", "Yearly")
        case .custom(let summary): return summary
        }
    }
}

/// A reminder's alert. Relative alerts are anchored to the due time; an
/// absolute one is a fixed moment.
package enum TaskAlert: Hashable, Sendable {
    case relative(minutesBefore: Int)
    case absolute(Date)

    package static let relativePresets = [0, 5, 15, 30, 60, 1440]

    package var isRelative: Bool {
        if case .relative = self { return true }
        return false
    }

    package var title: String { title(format: .twentyFourHour) }

    package func title(format: TimeFormat, dates: DatePresentationFormatter = .current) -> String {
        switch self {
        case .relative(let minutes):
            switch minutes {
            case 0: return L10n.tr("taskrecurrence.at.time.of.due.date", "At time of due date")
            case 1440: return L10n.tr("taskrecurrence.1.day.before", "1 day before")
            case 60: return L10n.tr("taskrecurrence.1.hour.before", "1 hour before")
            default: return L10n.tr("taskrecurrence.min.before", "\(String(describing: minutes)) min before")
            }
        case .absolute(let date):
            return dates.format(date, .short) + " " + format.time(date)
        }
    }
}
