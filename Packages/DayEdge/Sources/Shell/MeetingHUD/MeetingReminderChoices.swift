import Foundation

/// The same reminder commands are offered by both Meeting HUD sizes.
enum MeetingReminderOption: Hashable {
    case untilStart
    case minutes(Int)
    case custom

    var menuTitle: String {
        switch self {
        case .untilStart: L10n.tr("meetingreminderchoices.remind.at.start", "Remind at start")
        case .minutes(let count): L10n.tr("meeting.reminder.minutes", "In \(count) minutes")
        case .custom: L10n.tr("meetingreminderchoices.custom", "Custom…")
        }
    }
}

struct MeetingReminderChoices: Equatable {
    let primary: MeetingReminderOption
    let menu: [MeetingReminderOption]

    static func resolve(start: Date, now: Date) -> Self {
        if now < start {
            return Self(primary: .untilStart, menu: [.untilStart, .minutes(1), .minutes(5), .minutes(10), .custom])
        }
        return Self(primary: .minutes(1), menu: [.minutes(1), .minutes(5), .minutes(10), .minutes(15), .custom])
    }

    var primaryTitle: String {
        switch primary {
        case .untilStart: L10n.tr("meetingreminderchoices.remind.at.start", "Remind at start")
        case .minutes: L10n.tr("meetingreminderchoices.remind.in.1.min", "Remind in 1 min")
        case .custom: L10n.tr("meetingreminderchoices.custom", "Custom…")
        }
    }
}
