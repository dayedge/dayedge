import Foundation
import Domain

/// Selects the joinable event represented by the meeting status item.
enum CallReadinessStrategy: Equatable, Codable {
    /// Shows the join icon starting `minutes` before a call event's own
    /// start. Once "ready," that event stays current until either it ends
    /// or the *next* call-having event's own start time arrives —
    /// whichever comes first — so two back-to-back or overlapping calls
    /// never both claim the icon at once; the earlier one simply hands
    /// off right as the next one's start time is reached.
    case leadTime(minutes: Int)

    static let `default` = CallReadinessStrategy.leadTime(minutes: 15)

    /// Events already belong to today's agenda.
    func readyEvent(events: [AgendaEventModel], now: Date) -> AgendaEventModel? {
        switch self {
        case .leadTime(let minutes):
            return Self.leadTimeReadyEvent(events: events, now: now, leadMinutes: minutes)
        }
    }

    private static func leadTimeReadyEvent(
        events: [AgendaEventModel], now: Date, leadMinutes: Int
    ) -> AgendaEventModel? {
        let candidates: [ActiveSlotCandidate<AgendaEventModel>] = events
            .filter { $0.status != .cancelled && ($0.meetingLink?.canJoin ?? false) }
            .compactMap { event in
                guard let start = event.startDate else { return nil }
                return ActiveSlotCandidate(value: event, start: start, end: event.endDate ?? start)
            }
        return resolveActiveSlot(candidates, now: now, leadMinutes: leadMinutes)
    }
}

/// Quick Join's persisted lead window.
enum CallReadinessSettings {
    static let leadMinutesKey = "com.dayedge.callReadinessLeadMinutes"
    static let leadMinuteOptions = [5, 10, 15, 30]
    static let defaultLeadMinutes = 15

    /// Stored values outside the offered presets fall back to the default.
    static func normalizedLeadMinutes(_ value: Int) -> Int {
        leadMinuteOptions.contains(value) ? value : defaultLeadMinutes
    }

    static var strategy: CallReadinessStrategy {
        .leadTime(minutes: leadMinutes)
    }

    static func leadMinutes(defaults: UserDefaults) -> Int {
        guard let stored = defaults.object(forKey: leadMinutesKey) as? Int else { return defaultLeadMinutes }
        return normalizedLeadMinutes(stored)
    }

    static var leadMinutes: Int {
        get { leadMinutes(defaults: .standard) }
        set { UserDefaults.standard.set(newValue, forKey: leadMinutesKey) }
    }
}
