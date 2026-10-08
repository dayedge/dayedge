import Foundation
import Domain

/// Which number the menu bar's calendar badge shows — a small, swappable
/// "how do I turn today's agenda into one glanceable digit" strategy, in
/// the same spirit as Foundation's `FormatStyle`: one value that fully
/// determines the transform, so a future Settings UI can offer a plain
/// picker over `allCases` and nothing else in the app needs to change.
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

    /// `events` are assumed to already be exactly one day's (see
    /// `AppDelegate.refreshBadge`) — this only decides how to reduce that
    /// day down to one number, not which day.
    func badgeValue(events: [AgendaEventModel], now: Date, calendar: Calendar) -> Int {
        switch self {
        case .remainingEvents:
            let nowMinutes = Self.minutesSinceMidnight(of: now, calendar: calendar)
            return events.filter { Self.isRemaining($0, nowMinutes: nowMinutes) }.count
        case .acceptedEvents:
            return events.filter(Self.isAccepted).count
        case .acceptedRemainingEvents:
            let nowMinutes = Self.minutesSinceMidnight(of: now, calendar: calendar)
            return events.filter { Self.isAccepted($0) && Self.isRemaining($0, nowMinutes: nowMinutes) }.count
        case .totalEvents:
            return events.filter { $0.status != .cancelled }.count
        case .dayOfMonth:
            return calendar.component(.day, from: now)
        }
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

/// Persisted choice of `MenuBarBadgeStrategy` — the one seam a future
/// Settings "menu bar" pane reads from and writes to; nothing else in the
/// app should read/write this key directly.
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
