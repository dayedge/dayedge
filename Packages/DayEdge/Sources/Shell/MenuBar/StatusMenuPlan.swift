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
    /// Every meeting's alerts, for a while: its submenu's `.pause` rows.
    /// While paused, the row's title is `pausedTitle` (it says when they
    /// resume) and the submenu starts with Resume (`unmuteAll`).
    case pauseAlerts([StatusMenuItem], pausedTitle: String?)
    /// One way to pause — until the meeting in progress ends, or a
    /// Focus-style duration; `checked` when the pause came from it and
    /// choosing it now would end at exactly the same moment.
    case pause(PauseChoice, title: String, checked: Bool)
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
        case .pauseAlerts(_, let pausedTitle):
            return pausedTitle ?? L10n.tr("statusmenuplan.pause.meeting.alerts", "Pause Meeting Alerts")
        case .pause(_, let title, _): return title
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
        case .pauseAlerts(_, let pausedTitle): return pausedTitle == nil ? "pause.circle" : "pause.circle.fill"
        // A text-only submenu.
        case .pause, .unmuteAll: return nil
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
        var globalMute: (until: Date, chosen: PauseChoice?)?
        var dates: DatePresentationFormatter
        var timeFormat: TimeFormat
    }

    static let titleLimit = 40
    /// Shorter where the title sits inside a longer sentence.
    static let pauseTitleLimit = 30

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

        var choices = MuteUntilOption.available(now: inputs.now, calendar: inputs.calendar).map(PauseChoice.duration)
        if let meeting, let end = meeting.endDate, canPauseUntilEnd(meeting, now: inputs.now, calendar: inputs.calendar) {
            choices.insert(.meetingEnd(title: meeting.title, end: end), at: 0)
        }
        // A check only for a choice that still means this pause: "For 1 Hour"
        // stops matching as soon as time passes, a daypart doesn't, a moved
        // meeting no longer does.
        let rows = choices.map { choice in
            StatusMenuItem.pause(
                choice, title: pauseTitle(choice, timeFormat: inputs.timeFormat, calendar: inputs.calendar),
                checked: inputs.globalMute.map {
                    $0.chosen == choice && choice.endDate(now: inputs.now, calendar: inputs.calendar) == $0.until
                } ?? false
            )
        }
        let pausedTitle = inputs.globalMute.map { mute in
            Self.pausedTitle(until: mute.until, chosen: mute.chosen, now: inputs.now,
                             dates: inputs.dates.with(inputs.calendar), timeFormat: inputs.timeFormat)
        }
        let reminders: [StatusMenuItem] = [.pauseAlerts(rows, pausedTitle: pausedTitle)]

        return [[.open, .search, .ask], context, reminders, [.settings, .about], [.quit]]
            .filter { !$0.isEmpty }
    }

    /// Current meeting first (the latest-started if several), else the next
    /// one later today. Timed, not cancelled or declined.
    static func relevantMeeting(in events: [AgendaEventModel], now: Date) -> AgendaEventModel? {
        let meetings = events.filter { event in
            event.blocksTime && event.status != .untimed && event.startDate != nil && event.endDate != nil
        }
        let current = meetings
            .filter { $0.startDate! <= now && now < $0.endDate! }
            .max { $0.startDate! < $1.startDate! }
        if let current { return current }
        return meetings
            .filter { $0.startDate! > now }
            .min { $0.startDate! < $1.startDate! }
    }

    /// Pausing until a meeting ends is worth offering while it's in
    /// progress, ends later today and not within minutes.
    static func canPauseUntilEnd(_ meeting: AgendaEventModel, now: Date, calendar: Calendar) -> Bool {
        guard let start = meeting.startDate, let end = meeting.endDate else { return false }
        return start <= now && end.timeIntervalSince(now) >= 5 * 60 && calendar.isDate(end, inSameDayAs: now)
    }

    /// For 1 Hour, …, or Until “Design Review” Ends (11:00).
    static func pauseTitle(_ choice: PauseChoice, timeFormat: TimeFormat, calendar: Calendar) -> String {
        switch choice {
        case .duration(let option):
            return option.menuTitle
        case .meetingEnd(let title, let end):
            let name = quoted(title, limit: pauseTitleLimit)
            let time = timeFormat.time(end, calendar: calendar)
            return L10n.tr("statusmenuplan.pause.until.meeting.ends.at",
                           "Until \(String(describing: name)) Ends (\(String(describing: time)))")
        }
    }

    /// "Meeting Alerts Paused · Until 15:00" — the day only when it isn't
    /// today; a meeting's pause names the meeting instead.
    static func pausedTitle(until: Date, chosen: PauseChoice?, now: Date, dates: DatePresentationFormatter,
                            timeFormat: TimeFormat) -> String {
        let locale = dates.displayLocale
        if case .meetingEnd(let title, _) = chosen {
            let name = quoted(title, limit: pauseTitleLimit)
            return L10n.tr("statusmenuplan.meeting.alerts.paused.until.meeting.ends",
                           "Meeting Alerts Paused · Until \(String(describing: name)) Ends", locale: locale)
        }
        // Whole sentences per case: "tomorrow" after "until" takes its own form in some languages (Polish "do jutra").
        let time = timeFormat.time(until, calendar: dates.calendar)
        switch dates.dayOffset(until, from: now) {
        case 0:
            return L10n.tr("statusmenuplan.meeting.alerts.paused.until", "Meeting Alerts Paused · Until \(time)", locale: locale)
        case 1:
            return L10n.tr("statusmenuplan.meeting.alerts.paused.until.tomorrow", "Meeting Alerts Paused · Until Tomorrow, \(time)",
                           locale: locale)
        default:
            return L10n.tr("statusmenuplan.meeting.alerts.paused.until.date",
                           "Meeting Alerts Paused · Until \(dates.menuBarDate(until)), \(time)", locale: locale)
        }
    }

    /// “Title”, on one line and shortened so the menu stays narrow: cut on
    /// a word when one ends close by, never mid-character.
    static func quoted(_ title: String, limit: Int = titleLimit) -> String {
        let flat = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard flat.count > limit else { return "“\(flat)”" }
        let prefix = String(flat.prefix(limit - 1))
        var cut = prefix
        let endsOnWord = flat.dropFirst(limit - 1).first == " "
        // Back to the last whole word, if it ends close by.
        if !endsOnWord, let space = cut.lastIndex(of: " "), cut.distance(from: space, to: cut.endIndex) <= 10 {
            cut = String(cut[..<space])
        }
        while let last = cut.last, last.isWhitespace || last.isPunctuation { cut.removeLast() }
        return "“\(cut.isEmpty ? prefix : cut)…”"
    }
}
