import Foundation
import Domain

/// One row of the status item's right-click menu.
enum StatusMenuItem {
    case open, search, ask
    /// The relevant meeting, joinable.
    case join(AgendaEventModel)
    /// The relevant meeting, without a call link: shown in the app's Day view.
    case showEvent(AgendaEventModel, day: Date)
    case showTodayTasks(count: Int)
    case muteMeeting(AgendaEventModel)
    case restoreMeeting(AgendaEventModel)
    /// Every meeting's alerts, for a while (the Focus-style durations). While
    /// paused, the submenu starts with Resume (`unmuteAll`); `checked` is the
    /// duration the pause came from, only when choosing it now would end at
    /// exactly the same moment.
    case pauseAlerts([MuteUntilOption], isPaused: Bool, checked: MuteUntilOption?)
    /// Resume Meeting Alerts — the paused submenu's first row.
    case unmuteAll
    case settings, about, quit

    var title: String {
        switch self {
        case .open: return L10n.tr("statusmenuplan.open.dayedge", "Open DayEdge")
        case .search: return L10n.tr("statusmenuplan.search", "Search…")
        case .ask: return L10n.tr("statusmenuplan.ask.dayedge", "Ask DayEdge…")
        case .join(let event): return L10n.tr("statusmenuplan.join", "Join \(String(describing: StatusMenuPlan.quoted(event.title)))")
        case .showEvent(let event, _): return L10n.tr("statusmenuplan.show.in.calendar", "Show \(String(describing: StatusMenuPlan.quoted(event.title))) in Calendar")
        case .showTodayTasks(let count): return L10n.tr("statusmenuplan.show.today.s.tasks", "Show Today’s Tasks (\(String(describing: count)))")
        case .muteMeeting: return L10n.tr("statusmenuplan.mute.this.meeting", "Mute This Meeting")
        case .restoreMeeting: return L10n.tr("statusmenuplan.unmute.this.meeting", "Unmute This Meeting")
        case .pauseAlerts(_, let isPaused, _):
            return isPaused ? L10n.tr("statusmenuplan.meeting.alerts.paused", "Meeting Alerts Paused")
                : L10n.tr("statusmenuplan.pause.meeting.alerts", "Pause Meeting Alerts")
        case .unmuteAll: return L10n.tr("statusmenuplan.resume.meeting.alerts", "Resume Meeting Alerts")
        case .settings: return L10n.tr("statusmenuplan.settings", "Settings…")
        case .about: return L10n.tr("statusmenuplan.about.dayedge", "About DayEdge")
        case .quit: return L10n.tr("statusmenuplan.quit.dayedge", "Quit DayEdge")
        }
    }

    /// The row's SF Symbol — the same ones the app uses for these things
    /// (Ask's sparkles, Tasks' checklist). Quit has none, as in Apple's menus.
    var symbolName: String? {
        switch self {
        case .open: return "calendar"
        case .search: return "magnifyingglass"
        case .ask: return ViewMode.ask.symbolName
        case .join: return "video"
        case .showEvent: return ViewMode.day.symbolName
        case .showTodayTasks: return "checklist"
        case .muteMeeting: return "bell.slash"
        case .restoreMeeting: return "bell"
        case .pauseAlerts(_, let isPaused, _): return isPaused ? "pause.circle.fill" : "pause.circle"
        // In a text-only submenu, like the durations under it.
        case .unmuteAll: return nil
        case .settings: return "gearshape"
        case .about: return "info.circle"
        case .quit: return nil
        }
    }
}

/// What the status menu shows right now — "what can I do now?", not every
/// feature. Five stable sections — the app; now (the relevant meeting with
/// its own mute, today's tasks); pausing every meeting's alerts; Settings
/// and About; Quit — only the middle two change, and an empty section
/// simply isn't there (no disabled "No meetings" rows).
enum StatusMenuPlan {
    struct Inputs {
        var now: Date
        var calendar: Calendar
        /// Today's events.
        var events: [AgendaEventModel]
        /// Open tasks that are overdue or due today.
        var actionableTaskCount: Int
        var isMuted: (AgendaEventModel) -> Bool
        /// The global mute, while active.
        var globalMute: (until: Date, chosen: MuteUntilOption?)?
    }

    static let titleLimit = 40

    static func resolve(_ inputs: Inputs) -> [[StatusMenuItem]] {
        let meeting = relevantMeeting(in: inputs.events, now: inputs.now)

        var context: [StatusMenuItem] = []
        if let meeting {
            if meeting.meetingLink?.canJoin == true {
                context.append(.join(meeting))
            } else {
                let day = inputs.calendar.startOfDay(for: meeting.startDate ?? inputs.now)
                context.append(.showEvent(meeting, day: day))
            }
            // The meeting's own mute sits with it; the global mute, while on,
            // already covers it.
            if inputs.globalMute == nil, meeting.endDate != nil {
                context.append(inputs.isMuted(meeting) ? .restoreMeeting(meeting) : .muteMeeting(meeting))
            }
        }
        if inputs.actionableTaskCount > 0 {
            context.append(.showTodayTasks(count: inputs.actionableTaskCount))
        }

        let options = MuteUntilOption.available(now: inputs.now, calendar: inputs.calendar)
        // A check only for a choice that still means this pause: "For 1 Hour"
        // stops matching as soon as time passes, a daypart doesn't.
        let checked = inputs.globalMute.flatMap { mute in
            mute.chosen.flatMap { $0.endDate(now: inputs.now, calendar: inputs.calendar) == mute.until ? $0 : nil }
        }
        let reminders: [StatusMenuItem] = [.pauseAlerts(options, isPaused: inputs.globalMute != nil, checked: checked)]

        return [[.open, .search, .ask], context, reminders, [.settings, .about], [.quit]]
            .filter { !$0.isEmpty }
    }

    /// Current meeting first (the latest-started if several), else the next
    /// one later today. Timed, not cancelled or declined.
    static func relevantMeeting(in events: [AgendaEventModel], now: Date) -> AgendaEventModel? {
        let meetings = events.filter { event in
            !event.isAllDay && event.status != .cancelled && event.status != .untimed
                && event.startDate != nil && event.endDate != nil
        }
        let current = meetings
            .filter { $0.startDate! <= now && now < $0.endDate! }
            .max { $0.startDate! < $1.startDate! }
        if let current { return current }
        return meetings
            .filter { $0.startDate! > now }
            .min { $0.startDate! < $1.startDate! }
    }

    /// “Title”, shortened so the menu stays narrow.
    static func quoted(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let short = trimmed.count > titleLimit
            ? String(trimmed.prefix(titleLimit - 1)).trimmingCharacters(in: .whitespaces) + "…"
            : trimmed
        return "“\(short)”"
    }
}
