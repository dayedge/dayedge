import Foundation

/// "Mute Until ›" in the status menu: silence every the app meeting
/// reminder for a while, in Focus-like words rather than clock times.
/// Dayparts that have (nearly) passed aren't offered.
package enum MuteUntilOption: String, CaseIterable, Hashable {
    case oneHour, afternoon, evening, tomorrow

    /// Where each daypart starts.
    package static let afternoonHour = 14
    package static let eveningHour = 18
    package static let morningHour = 8
    /// A daypart closer than this isn't worth offering.
    package static let minimumLead: TimeInterval = 30 * 60

    package var menuTitle: String {
        switch self {
        case .oneHour: return L10n.tr("muteuntiloption.for.1.hour", "For 1 Hour")
        case .afternoon: return L10n.tr("muteuntiloption.until.this.afternoon", "Until This Afternoon")
        case .evening: return L10n.tr("muteuntiloption.until.this.evening", "Until This Evening")
        case .tomorrow: return L10n.tr("muteuntiloption.until.tomorrow", "Until Tomorrow")
        }
    }

    /// When the mute ends.
    package func endDate(now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        func at(_ hour: Int, daysAhead: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: daysAhead, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        }
        switch self {
        case .oneHour: return now.addingTimeInterval(60 * 60)
        case .afternoon: return at(Self.afternoonHour)
        case .evening: return at(Self.eveningHour)
        case .tomorrow: return at(Self.morningHour, daysAhead: 1)
        }
    }

    /// What the submenu offers now, in order.
    package static func available(now: Date, calendar: Calendar) -> [MuteUntilOption] {
        allCases.filter { option in
            switch option {
            case .oneHour, .tomorrow: return true
            case .afternoon, .evening:
                return option.endDate(now: now, calendar: calendar).timeIntervalSince(now) > minimumLead
            }
        }
    }
}

/// A way to pause every meeting's alerts; kept with the pause so the menu
/// can say it back.
package enum PauseChoice: Equatable {
    case duration(MuteUntilOption)
    /// Until the meeting then in progress ends: its title and end as they were then.
    case meetingEnd(title: String, end: Date)

    /// When the pause ends.
    package func endDate(now: Date, calendar: Calendar) -> Date {
        switch self {
        case .duration(let option): return option.endDate(now: now, calendar: calendar)
        case .meetingEnd(_, let end): return end
        }
    }
}
