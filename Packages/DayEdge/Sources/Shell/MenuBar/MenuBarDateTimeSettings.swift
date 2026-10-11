import Foundation
import Domain

enum MenuBarDateTimeFormat: String, CaseIterable, Identifiable {
    case compact, date, time, long, custom

    var id: Self { self }

    var title: String {
        switch self {
        case .compact: L10n.tr("menubar.datetime.compact", "Compact")
        case .date: L10n.tr("menubar.datetime.date", "Date")
        case .time: L10n.tr("menubar.datetime.time", "Time")
        case .long: L10n.tr("menubar.datetime.long", "Long")
        case .custom: L10n.tr("dateformatrows.custom", "Custom…")
        }
    }

    func text(at now: Date, pattern: String, formatter: DatePresentationFormatter, timeFormat: TimeFormat) -> String {
        let date = formatter.dayMonth(now, abbreviated: true)
        let time = timeFormat.time(now, calendar: formatter.calendar)
        switch self {
        case .compact: return "\(date)  \(time)"
        case .date: return date
        case .time: return time
        case .long: return "\(formatter.menuBarDate(now))  \(time)"
        case .custom:
            guard DatePresentationFormatter.validate(pattern, sample: now, using: formatter, purpose: .menuBar).isValid else {
                return MenuBarDateTimeFormat.compact.text(at: now, pattern: "", formatter: formatter, timeFormat: timeFormat)
            }
            return formatter.format(now, .custom(pattern))
        }
    }
}

enum MenuBarItemPresentation: String, CaseIterable, Identifiable {
    case icon, dateTime, iconAndDateTime

    var id: Self { self }
    var showsIcon: Bool { self != .dateTime }
    var showsDateTime: Bool { self != .icon }

    var title: String {
        switch self {
        case .icon: L10n.tr("menubar.item.icon", "Icon")
        case .dateTime: L10n.tr("menubar.item.date.time", "Date & Time")
        case .iconAndDateTime: L10n.tr("menubar.item.icon.date.time", "Icon and Date & Time")
        }
    }
}

struct MenuBarDateTimeConfiguration: Equatable {
    var presentation = MenuBarItemPresentation.icon
    var format = MenuBarDateTimeFormat.compact
    var customPattern = ""

    func text(at now: Date, formatter: DatePresentationFormatter, timeFormat: TimeFormat) -> String {
        presentation.showsDateTime ? format.text(at: now, pattern: customPattern, formatter: formatter, timeFormat: timeFormat) : ""
    }
}

enum MenuBarDateTimeSettings {
    static let presentationKey = "com.dayedge.menuBarItem.presentation"
    static let legacyEnabledKey = "com.dayedge.menuBarDateTime.enabled"
    static let formatKey = "com.dayedge.menuBarDateTime.format"
    static let customPatternKey = "com.dayedge.menuBarDateTime.customPattern"

    /// Retire the old toggle once, without touching format or badge preferences.
    static func presentation(defaults: UserDefaults = .standard) -> MenuBarItemPresentation {
        if let raw = defaults.string(forKey: presentationKey) {
            return MenuBarItemPresentation(rawValue: raw) ?? .icon
        }
        let mode: MenuBarItemPresentation = defaults.bool(forKey: legacyEnabledKey) ? .iconAndDateTime : .icon
        defaults.set(mode.rawValue, forKey: presentationKey)
        defaults.removeObject(forKey: legacyEnabledKey)
        return mode
    }

    static func configuration(defaults: UserDefaults = .standard) -> MenuBarDateTimeConfiguration {
        MenuBarDateTimeConfiguration(
            presentation: presentation(defaults: defaults),
            format: defaults.string(forKey: formatKey).flatMap(MenuBarDateTimeFormat.init(rawValue:)) ?? .compact,
            customPattern: defaults.string(forKey: customPatternKey) ?? ""
        )
    }
}
