import Foundation
import Domain

struct MenuBarEventIndicatorConfiguration: Equatable {
    var isEnabled: Bool
    var leadTimeMinutes: Int
    var showsEventTitle: Bool
    var showsEventEndTime: Bool
    var showsCalendarAccent: Bool
    var showsOngoingEvents: Bool
    var showsRemainingTimeNearEnd: Bool
    var showsFreeTimeTransition: Bool
    var freeTimeTransitionMinutes: Int
    var minimumFreeGapMinutes: Int

    static let `default` = MenuBarEventIndicatorConfiguration(
        isEnabled: true,
        leadTimeMinutes: 15,
        showsEventTitle: true,
        showsEventEndTime: true,
        showsCalendarAccent: true,
        showsOngoingEvents: true,
        showsRemainingTimeNearEnd: true,
        showsFreeTimeTransition: false,
        freeTimeTransitionMinutes: 5,
        minimumFreeGapMinutes: 15
    )
}

enum MenuBarEventIndicatorState: Equatable {
    case upcoming(event: AgendaEventModel, minutesUntilStart: Int)
    case ongoing(event: AgendaEventModel, minutesRemaining: Int?)
    case free(until: Date)

    var event: AgendaEventModel? {
        switch self {
        case .upcoming(let event, _), .ongoing(let event, _): event
        case .free: nil
        }
    }

    func label(configuration: MenuBarEventIndicatorConfiguration, calendar: Calendar,
               format: TimeFormat = .twentyFourHour) -> String {
        switch self {
        case .free(let until):
            return L10n.tr("menubareventindicator.free.until", "Free until \(String(describing: format.time(until, calendar: calendar)))")

        case .upcoming(let event, let minutes):
            var parts = [minutes <= 0 ? L10n.tr("menubareventindicator.soon", "Soon") : L10n.tr("menubareventindicator.in.m", "in \(String(describing: minutes))m")]
            appendEventDetails(event, to: &parts, configuration: configuration, calendar: calendar, format: format)
            return parts.joined(separator: " · ")

        case .ongoing(let event, let minutesRemaining):
            var parts = [minutesRemaining.map { L10n.tr("menubareventindicator.m.left", "\(String(describing: $0))m left") } ?? "NOW"]
            appendEventDetails(event, to: &parts, configuration: configuration, calendar: calendar, format: format)
            return parts.joined(separator: " · ")
        }
    }

    private func appendEventDetails(
        _ event: AgendaEventModel,
        to parts: inout [String],
        configuration: MenuBarEventIndicatorConfiguration,
        calendar: Calendar,
        format: TimeFormat
    ) {
        if configuration.showsEventTitle, !event.title.isEmpty {
            parts.append(event.title)
        }
        if configuration.showsEventEndTime, let endTime = event.endText(format, calendar: calendar) {
            parts.append("→\(endTime)")
        }
    }
}

enum MenuBarEventIndicatorResolver {
    private struct TimedEvent {
        let event: AgendaEventModel
        let interval: DateInterval
    }

    static func resolve(
        events: [AgendaEventModel],
        on day: Date,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent,
        configuration: MenuBarEventIndicatorConfiguration
    ) -> MenuBarEventIndicatorState? {
        guard configuration.isEnabled else { return nil }

        let timed = events.compactMap { event -> TimedEvent? in
            guard event.status != .cancelled,
                  !event.isAllDay,
                  let interval = agendaInterval(for: event, on: day, calendar: calendar) else { return nil }
            return TimedEvent(event: event, interval: interval)
        }

        let ongoingEvents = timed
            .filter { $0.interval.start <= now && now < $0.interval.end }
            .sorted(by: preferredOngoingEvent)
        if configuration.showsOngoingEvents, let ongoing = ongoingEvents.first {
            let remaining = Int(ceil(ongoing.interval.end.timeIntervalSince(now) / 60))
            let displayedRemaining = configuration.showsRemainingTimeNearEnd && remaining <= 10
                ? max(1, remaining)
                : nil
            return .ongoing(event: ongoing.event, minutesRemaining: displayedRemaining)
        }

        let next = timed
            .filter { $0.interval.start > now }
            .min(by: chronologicalOrder)
        if let next {
            let secondsUntilStart = next.interval.start.timeIntervalSince(now)
            if secondsUntilStart <= TimeInterval(configuration.leadTimeMinutes * 60) {
                return .upcoming(
                    event: next.event,
                    minutesUntilStart: max(1, Int(ceil(secondsUntilStart / 60)))
                )
            }
        }

        guard configuration.showsFreeTimeTransition,
              configuration.freeTimeTransitionMinutes > 0,
              ongoingEvents.isEmpty,
              let next,
              let previous = timed
                .filter({ $0.interval.end <= now })
                .max(by: { $0.interval.end < $1.interval.end }) else { return nil }

        let elapsed = now.timeIntervalSince(previous.interval.end)
        let transitionDuration = TimeInterval(configuration.freeTimeTransitionMinutes * 60)
        let freeGap = next.interval.start.timeIntervalSince(previous.interval.end)
        guard elapsed >= 0,
              elapsed < transitionDuration,
              freeGap >= TimeInterval(configuration.minimumFreeGapMinutes * 60) else { return nil }
        return .free(until: next.interval.start)
    }

    private static func preferredOngoingEvent(_ lhs: TimedEvent, _ rhs: TimedEvent) -> Bool {
        let lhsCanJoin = lhs.event.meetingLink?.canJoin ?? false
        let rhsCanJoin = rhs.event.meetingLink?.canJoin ?? false
        if lhsCanJoin != rhsCanJoin { return lhsCanJoin }
        if lhs.interval.start != rhs.interval.start { return lhs.interval.start > rhs.interval.start }
        return lhs.event.id < rhs.event.id
    }

    private static func chronologicalOrder(_ lhs: TimedEvent, _ rhs: TimedEvent) -> Bool {
        if lhs.interval.start != rhs.interval.start { return lhs.interval.start < rhs.interval.start }
        return lhs.event.id < rhs.event.id
    }
}

enum MenuBarEventIndicatorSettings {
    static let enabledKey = "com.dayedge.menuBarEventIndicator.enabled"
    static let leadTimeKey = "com.dayedge.menuBarEventIndicator.leadMinutes"
    static let showTitleKey = "com.dayedge.menuBarEventIndicator.showTitle"
    static let showEndTimeKey = "com.dayedge.menuBarEventIndicator.showEndTime"
    static let showAccentKey = "com.dayedge.menuBarEventIndicator.showAccent"
    static let showOngoingKey = "com.dayedge.menuBarEventIndicator.showOngoing"
    static let showRemainingKey = "com.dayedge.menuBarEventIndicator.showRemainingNearEnd"
    static let showFreeTransitionKey = "com.dayedge.menuBarEventIndicator.showFreeTransition"
    static let freeTransitionDurationKey = "com.dayedge.menuBarEventIndicator.freeTransitionMinutes"
    static let minimumFreeGapKey = "com.dayedge.menuBarEventIndicator.minimumFreeGapMinutes"

    static var configuration: MenuBarEventIndicatorConfiguration {
        let defaults = UserDefaults.standard
        let fallback = MenuBarEventIndicatorConfiguration.default
        return MenuBarEventIndicatorConfiguration(
            isEnabled: bool(forKey: enabledKey, default: fallback.isEnabled, defaults: defaults),
            leadTimeMinutes: integer(forKey: leadTimeKey, default: fallback.leadTimeMinutes, defaults: defaults),
            showsEventTitle: bool(forKey: showTitleKey, default: fallback.showsEventTitle, defaults: defaults),
            showsEventEndTime: bool(forKey: showEndTimeKey, default: fallback.showsEventEndTime, defaults: defaults),
            showsCalendarAccent: bool(forKey: showAccentKey, default: fallback.showsCalendarAccent, defaults: defaults),
            showsOngoingEvents: bool(forKey: showOngoingKey, default: fallback.showsOngoingEvents, defaults: defaults),
            showsRemainingTimeNearEnd: bool(forKey: showRemainingKey, default: fallback.showsRemainingTimeNearEnd, defaults: defaults),
            showsFreeTimeTransition: bool(forKey: showFreeTransitionKey, default: fallback.showsFreeTimeTransition, defaults: defaults),
            freeTimeTransitionMinutes: integer(
                forKey: freeTransitionDurationKey,
                default: fallback.freeTimeTransitionMinutes,
                defaults: defaults
            ),
            minimumFreeGapMinutes: integer(
                forKey: minimumFreeGapKey,
                default: fallback.minimumFreeGapMinutes,
                defaults: defaults
            )
        )
    }

    private static func bool(forKey key: String, default fallback: Bool, defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    private static func integer(forKey key: String, default fallback: Int, defaults: UserDefaults) -> Int {
        defaults.object(forKey: key) == nil ? fallback : defaults.integer(forKey: key)
    }
}
