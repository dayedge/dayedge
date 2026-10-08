import Foundation

/// First day of the week in the month grid.
package enum WeekStart: String, CaseIterable, Identifiable {
    case system
    case monday
    case sunday

    package var id: String { rawValue }

    package var title: String {
        switch self {
        case .system: return L10n.tr("generalsettings.system.setting", "System Setting")
        case .monday: return L10n.tr("generalsettings.monday", "Monday")
        case .sunday: return L10n.tr("generalsettings.sunday", "Sunday")
        }
    }

    /// `Calendar.firstWeekday` value (1 = Sunday).
    package func firstWeekday(locale: Locale = .autoupdatingCurrent) -> Int {
        switch self {
        case .system:
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = locale
            return calendar.firstWeekday
        case .monday: return 2
        case .sunday: return 1
        }
    }
}

/// General preferences. Keys are read here and written by Settings.
package enum GeneralSettings {
    package static let defaultViewKey = "com.dayedge.general.defaultView"
    package static let weekStartKey = "com.dayedge.general.weekStart"
    package static let showsWeatherKey = "com.dayedge.general.showsWeather"
    package static let showsDeclinedKey = "com.dayedge.general.showsDeclined"
    package static let dayStartHourKey = "com.dayedge.general.dayStartHour"
    package static let showsWeekNumbersKey = "com.dayedge.general.showsWeekNumbers"

    package static let dayStartHourOptions = [6, 7, 8, 9, 10]
    package static let defaultDayStartHour = 8

    package static func defaultView(defaults: UserDefaults = .standard) -> ViewMode {
        defaults.string(forKey: defaultViewKey).flatMap(ViewMode.init(settingsValue:)) ?? .month
    }

    package static func weekStart(defaults: UserDefaults = .standard) -> WeekStart {
        defaults.string(forKey: weekStartKey).flatMap(WeekStart.init(rawValue:)) ?? .system
    }

    package static func showsDeclined(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: showsDeclinedKey) as? Bool ?? false
    }

    package static func showsWeekNumbers(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: showsWeekNumbersKey) as? Bool ?? false
    }

    package static func dayStartHour(defaults: UserDefaults = .standard) -> Int {
        guard let stored = defaults.object(forKey: dayStartHourKey) as? Int,
              dayStartHourOptions.contains(stored) else { return defaultDayStartHour }
        return stored
    }

    package static func showsWeather(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: showsWeatherKey) as? Bool ?? true
    }
}

extension ViewMode {
    /// Stable persisted value for the "Default view" setting.
    package var settingsValue: String {
        switch self {
        case .month: return "month"
        case .day: return "day"
        case .tasks: return "tasks"
        case .ask: return "ask"
        }
    }

    package init?(settingsValue: String) {
        guard let mode = Self.allCases.first(where: { $0.settingsValue == settingsValue }) else { return nil }
        self = mode
    }
}
