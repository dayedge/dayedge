import Foundation
import Domain

struct MenuBarBadgeContent: Equatable {
    let number: Int
    let isOverflow: Bool
}

/// Decides the displayed number and whether it needs an overflow glyph.
enum MenuBarBadgeStrategy: String, CaseIterable, Identifiable, Codable {
    case remainingEvents
    case acceptedEvents
    case acceptedRemainingEvents
    case totalEvents
    case dayOfMonth

    var id: Self { self }

    var displayName: String {
        switch self {
        case .remainingEvents: return L10n.tr("menubarbadgestrategy.remaining.events.today", "Remaining Events Today")
        case .acceptedEvents: return L10n.tr("menubarbadgestrategy.accepted.events.today", "Accepted Events Today")
        case .acceptedRemainingEvents: return L10n.tr("menubarbadgestrategy.accepted.still.remaining", "Accepted, Still Remaining")
        case .totalEvents: return L10n.tr("menubarbadgestrategy.total.events.today", "Total Events Today")
        case .dayOfMonth: return L10n.tr("menubarbadgestrategy.day.of.month", "Day of Month")
        }
    }

    /// Events already belong to today and respect calendar visibility.
    func badgeContent(events: [AgendaEventModel], now: Date, calendar: Calendar) -> MenuBarBadgeContent {
        let count: Int
        switch self {
        case .remainingEvents:
            let nowMinutes = Self.minutesSinceMidnight(of: now, calendar: calendar)
            count = events.filter { Self.isRemaining($0, nowMinutes: nowMinutes) }.count
        case .acceptedEvents:
            count = events.filter(Self.isAccepted).count
        case .acceptedRemainingEvents:
            let nowMinutes = Self.minutesSinceMidnight(of: now, calendar: calendar)
            count = events.filter { Self.isAccepted($0) && Self.isRemaining($0, nowMinutes: nowMinutes) }.count
        case .totalEvents:
            count = events.filter { $0.status != .cancelled }.count
        case .dayOfMonth:
            return MenuBarBadgeContent(number: calendar.component(.day, from: now), isOverflow: false)
        }
        return MenuBarBadgeContent(number: min(count, 9), isOverflow: count > 9)
    }

    private static func minutesSinceMidnight(of date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    /// Non-cancelled and not yet ended — all-day/untimed events count for
    /// the whole day regardless of the current time.
    private static func isRemaining(_ event: AgendaEventModel, nowMinutes: Int) -> Bool {
        guard event.status != .cancelled else { return false }
        guard let endMinutes = event.endMinutesSinceMidnight else { return true }
        return endMinutes >= nowMinutes
    }

    private static func isAccepted(_ event: AgendaEventModel) -> Bool {
        event.status != .cancelled && event.myResponseStatus == .accepted
    }
}

/// Persisted choice shared by Settings and the menu bar.
enum MenuBarBadgeSettings {
    static let strategyKey = "com.dayedge.menuBarBadgeStrategy"

    static func strategy(defaults: UserDefaults = .standard) -> MenuBarBadgeStrategy {
        defaults.string(forKey: strategyKey).flatMap(MenuBarBadgeStrategy.init) ?? .remainingEvents
    }

    static var strategy: MenuBarBadgeStrategy {
        get { strategy(defaults: .standard) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: strategyKey) }
    }
}
