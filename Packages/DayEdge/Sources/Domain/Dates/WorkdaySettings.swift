import Foundation

/// Which weekdays count as the weekend for workday math. Stored by raw
/// value in `UserDefaults`; `.automatic` follows the holiday region's
/// locale conventions (e.g. Friday–Saturday in some regions).
package enum WorkWeek: String, CaseIterable, Identifiable {
    case automatic
    case mondayFriday
    case sundayThursday
    case mondaySaturday

    package var id: String { rawValue }

    package var title: String {
        switch self {
        case .automatic: return L10n.tr("workdaysettings.automatic", "Automatic")
        case .mondayFriday: return L10n.tr("workdaysettings.monday.friday", "Monday–Friday")
        case .sundayThursday: return L10n.tr("workdaysettings.sunday.thursday", "Sunday–Thursday")
        case .mondaySaturday: return L10n.tr("workdaysettings.monday.saturday", "Monday–Saturday")
        }
    }

    /// `Calendar` weekday numbers (1 = Sunday) that are NOT work days.
    /// `nil` for `.automatic`, which needs a region to resolve.
    package var fixedWeekendWeekdays: Set<Int>? {
        switch self {
        case .automatic: return nil
        case .mondayFriday: return [1, 7]
        case .sundayThursday: return [6, 7]
        case .mondaySaturday: return [1]
        }
    }
}

/// Preferences for the month view's workday count and holiday marking.
/// "Holiday region" is a preference, not a calendar: nothing here touches
/// EventKit.
package enum WorkdaySettings {
    package static let showCountKey = "com.dayedge.workdays.showCount"
    package static let regionCodeKey = "com.dayedge.workdays.regionCode"
    package static let workWeekKey = "com.dayedge.workdays.workWeek"
    package static let markHolidaysKey = "com.dayedge.workdays.markHolidays"

    /// Empty stored region means "follow the macOS region".
    package static let automaticRegion = ""

    package struct Configuration: Equatable {
        package var showCount: Bool
        package var markHolidays: Bool
        /// Effective ISO 3166-1 region (override, else the macOS region).
        package var regionCode: String?
        package var weekendWeekdays: Set<Int>
    }

    package static func configuration(
        defaults: UserDefaults = .standard,
        locale: Locale = .current
    ) -> Configuration {
        let stored = defaults.string(forKey: regionCodeKey) ?? automaticRegion
        let region = effectiveRegion(override: stored, locale: locale)
        let workWeek = defaults.string(forKey: workWeekKey).flatMap(WorkWeek.init(rawValue:)) ?? .automatic
        return Configuration(
            showCount: defaults.object(forKey: showCountKey) as? Bool ?? true,
            markHolidays: defaults.object(forKey: markHolidaysKey) as? Bool ?? true,
            regionCode: region,
            weekendWeekdays: workWeek.fixedWeekendWeekdays ?? localeWeekendWeekdays(region: region)
        )
    }

    package static func effectiveRegion(override: String, locale: Locale = .current) -> String? {
        override.isEmpty ? locale.region?.identifier : override
    }

    /// Weekend weekdays (1 = Sunday) for a region, from macOS's own
    /// regional data. Falls back to Saturday/Sunday.
    package static func localeWeekendWeekdays(region: String?) -> Set<Int> {
        guard let region else { return [1, 7] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_\(region)")
        // 2026-09-06 is a Sunday; walk a full week from it.
        let sunday = DateComponents(calendar: calendar, year: 2026, month: 9, day: 6).date ?? Date()
        var weekend = Set<Int>()
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: sunday) else { continue }
            if calendar.isDateInWeekend(day) { weekend.insert(offset + 1) }
        }
        return weekend.isEmpty || weekend.count > 3 ? [1, 7] : weekend
    }
}

/// A selectable holiday region for the settings picker.
package struct HolidayRegionOption: Identifiable, Hashable {
    package let code: String
    package let name: String
    package var id: String { code }

    package var flag: String {
        code.uppercased().unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }
            .map(String.init).joined()
    }

    package var label: String { "\(flag) \(name)" }

    /// macOS's own ISO region list, localized, limited to `supported`
    /// (the regions the holiday source can serve) when known.
    package static func options(supported: Set<String>?, locale: Locale = .current) -> [HolidayRegionOption] {
        Locale.Region.isoRegions
            .map(\.identifier)
            .filter { $0.count == 2 && (supported?.contains($0) ?? true) }
            .compactMap { code in
                locale.localizedString(forRegionCode: code).map { HolidayRegionOption(code: code, name: $0) }
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    package static func name(for code: String, locale: Locale = .current) -> String {
        locale.localizedString(forRegionCode: code) ?? code
    }
}
