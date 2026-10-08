import Foundation
import Domain

/// One row of the search palette. Precedence is deterministic — a strict
/// date → "Go to"; else a parsed draft → "Create" a task and/or an event
/// (`QuickAddKindDecision` picks which, the likelier first); then Search
/// (events and tasks matching the query, enabled when it has a searchable
/// word) and Ask, always listed.
package struct PaletteAction: Identifiable, Equatable {
    package enum Kind: Equatable {
        case goToDate
        case createTask
        case createEvent
        case search
        case askAI
    }

    package var id: Kind { kind }
    package let kind: Kind
    package let title: String
    /// What the query was understood as ("Friday, 2 Oct · 10:00 · Work"),
    /// or a placeholder's "Coming later".
    package let subtitle: String?
    /// Disabled actions render quietly, can't be selected and never run.
    package let isEnabled: Bool
    /// Tab expands it in place (Quick Add).
    package let supportsRefinement: Bool
    /// What VoiceOver reads ("Create task, Dentysta").
    package var accessibilityLabel: String?
    /// Create event: whether its time is free (nil = not checked, all day).
    package var conflict: EventConflict?

    /// The verb on the footer's ↵ hint.
    package var executeLabel: String {
        switch kind {
        case .goToDate: return L10n.tr("paletteaction.go", "Go")
        case .createTask, .createEvent: return L10n.tr("paletteaction.create", "Create")
        case .search: return L10n.tr("paletteaction.show.all", "Show All")
        case .askAI: return L10n.tr("paletteaction.ask", "Ask")
        }
    }

    /// The verb on the footer's ⇥ hint.
    package var refineLabel: String { kind == .createTask || kind == .createEvent ? L10n.tr("paletteaction.edit", "Edit") : L10n.tr("paletteaction.refine", "Refine") }
}

/// One key hint in the palette's footer: a glyph and what it does now.
package struct PaletteKeyHint: Equatable, Identifiable {
    package enum Key: Equatable {
        case tab, returnKey, commandReturn, escape

        package var glyph: String {
            switch self {
            case .tab: return "⇥"
            case .returnKey: return "↵"
            case .commandReturn: return "⌘↵"
            case .escape: return "esc"
            }
        }

        package var spokenName: String {
            switch self {
            case .tab: return "Tab"
            case .returnKey: return "Return"
            case .commandReturn: return L10n.tr("paletteaction.command.return", "Command-Return")
            case .escape: return L10n.tr("paletteaction.escape", "Escape")
            }
        }
    }

    package var id: String { glyph + label }
    package let key: Key
    package let label: String
    package var glyph: String { key.glyph }
    /// "Edit with Tab", "Create with Return".
    package var accessibilityLabel: String { "\(label) with \(key.spokenName)" }
}

package enum PaletteActions {
    /// The footer: what the keys do for the selected action, right now.
    /// Nothing selected (only placeholders) → no hints.
    package static func hints(for selected: PaletteAction?, isRefining: Bool) -> [PaletteKeyHint] {
        guard let selected, selected.isEnabled else { return [] }
        // Search previews; Tab opens the detailed Search view.
        if selected.kind == .search { return [PaletteKeyHint(key: .tab, label: L10n.tr("paletteaction.more", "More"))] }
        if isRefining {
            // Tab is ordinary field traversal here — not worth a hint; Return
            // works the focused field, ⌘Return creates.
            return [PaletteKeyHint(key: .escape, label: L10n.tr("paletteaction.collapse", "Back")),
                    PaletteKeyHint(key: .commandReturn, label: selected.executeLabel)]
        }
        let refine = selected.supportsRefinement ? [PaletteKeyHint(key: .tab, label: selected.refineLabel)] : []
        return refine + [PaletteKeyHint(key: .returnKey, label: selected.executeLabel)]
    }

    /// A selected Search result: Return inspects it, Tab shows it where it
    /// lives.
    package static func hints(for result: SearchResultRowItem) -> [PaletteKeyHint] {
        [PaletteKeyHint(key: .returnKey, label: L10n.tr("paletteaction.details", "Details")),
         PaletteKeyHint(key: .tab, label: result.result.isTask ? L10n.tr(
             "paletteaction.show.in.tasks", "Show in Tasks"
         ) : L10n.tr(
             "paletteaction.show.in.calendar", "Show in Calendar"
         ))]
    }

    /// Listed under every query, after what it was understood as. Search's
    /// subtitle (result counts) is live — drawn from the results.
    package static func alwaysListed(isSearchable: Bool) -> [PaletteAction] {
        [
            PaletteAction(kind: .search, title: L10n.tr("paletteaction.search", "Search"), subtitle: nil, isEnabled: isSearchable, supportsRefinement: false,
                          accessibilityLabel: L10n.tr("paletteaction.search.events.and.tasks", "Search events and tasks")),
            PaletteAction(kind: .askAI, title: L10n.tr("paletteaction.ask", "Ask"), subtitle: nil, isEnabled: true, supportsRefinement: false)
        ]
    }

    /// The rows for a resolved query, in their fixed order. A task needs a
    /// list to go to, an event a writable calendar.
    package static func build(dateIntent: SearchIntent?, task: QuickAddDraft?, lists: [CalendarSource],
                              calendars: [CalendarSource] = [], conflict: EventConflict? = nil,
                              isSearchable: Bool = true, referenceDate: Date, calendar: Calendar,
                              format: TimeFormat = .twentyFourHour, dates: DatePresentationFormatter = .current) -> [PaletteAction] {
        var actions: [PaletteAction] = []
        if let dateIntent, dateIntent.isNavigation {
            let title = SearchSuggestion.make(for: dateIntent, referenceDate: referenceDate, calendar: calendar, dates: dates).title
            actions.append(PaletteAction(kind: .goToDate, title: title, subtitle: nil, isEnabled: true,
                                         supportsRefinement: false, accessibilityLabel: title))
        } else if let task {
            let kinds = QuickAddKindDecision.decide(task).kinds.filter { kind in
                kind == .task ? !lists.isEmpty : !calendars.isEmpty
            }
            // Both offered: each says what it makes.
            let isChoice = kinds.count > 1
            for kind in kinds {
                switch kind {
                case .task:
                    actions.append(PaletteAction(
                        kind: .createTask, title: isChoice ? L10n.tr(
                            "paletteaction.create.task", "Create task “\(String(describing: task.title))”"
                        ) : L10n.tr(
                            "paletteaction.create.618d1a", "Create “\(String(describing: task.title))”"
                        ),
                        subtitle: summary(of: task, lists: lists, referenceDate: referenceDate, calendar: calendar, format: format, dates: dates),
                        isEnabled: true, supportsRefinement: true, accessibilityLabel: L10n.tr("paletteaction.create.task.cc3d84", "Create task, \(String(describing: task.title))")
                    ))
                case .event:
                    let event = task.eventDraft(calendar: calendar, referenceDate: referenceDate)
                    actions.append(PaletteAction(
                        kind: .createEvent, title: L10n.tr("paletteaction.create.event", "Create event “\(String(describing: event.title))”"),
                        subtitle: summary(of: event, recurrence: task.recurrence, calendars: calendars,
                                          referenceDate: referenceDate, calendar: calendar, format: format, dates: dates),
                        isEnabled: true, supportsRefinement: true, accessibilityLabel: L10n.tr(
                            "paletteaction.create.event.8833bc", "Create event, \(String(describing: event.title))"
                        ),
                        conflict: event.isAllDay ? nil : conflict
                    ))
                }
            }
        }
        return actions + alwaysListed(isSearchable: isSearchable)
    }

    /// An event's line: "Friday, 2 Oct 10:00–11:00 · Work · Office" — the
    /// end shown even when defaulted, so its length is never a surprise.
    package static func summary(of event: EventDraft, recurrence: TaskRecurrenceRule?, calendars: [CalendarSource],
                                referenceDate: Date, calendar: Calendar, format: TimeFormat = .twentyFourHour,
                                dates: DatePresentationFormatter = .current) -> String {
        let day = { (date: Date) in SearchSuggestion.dayLabel(for: date, referenceDate: referenceDate, calendar: calendar, dates: dates) }
        let hm = { (date: Date) in format.time(date, calendar: calendar) }
        var when = recurrence?.summary ?? day(event.start)
        if event.isAllDay {
            if !calendar.isDate(event.end, inSameDayAs: event.start) { when += " – " + day(event.end) }
            when += L10n.tr("paletteaction.all.day", " · All day")
        } else if calendar.isDate(event.end, inSameDayAs: event.start) || event.end.timeIntervalSince(event.start) < 86_400 {
            // Tight, as the line is: "10:00–11:00", "10:30–11:00am".
            when += " " + format.range(event.start, event.end, calendar: calendar).replacingOccurrences(of: " – ", with: "–")
        } else {
            when += " \(hm(event.start)) – \(day(event.end)) \(hm(event.end))"
        }
        var parts = [when]
        if let id = event.calendarIdentifier, let source = calendars.first(where: { $0.id == id }) { parts.append(source.title) }
        if let location = event.location { parts.append(location) }
        return parts.joined(separator: " · ")
    }

    /// What was understood, and only that — one compact line beside the
    /// title: "Friday, 2 Oct 10:00 · Work", "Every Friday 17:00 · Work ·
    /// High Priority" (when and its time read as one block). nil when there
    /// is nothing beyond the title.
    package static func summary(of task: QuickAddDraft, lists: [CalendarSource], referenceDate: Date, calendar: Calendar,
                                format: TimeFormat = .twentyFourHour, dates: DatePresentationFormatter = .current) -> String? {
        var parts: [String] = []
        var when: [String] = []
        if let rule = task.recurrence {
            when.append(rule.summary)
        } else if let day = task.day {
            when.append(SearchSuggestion.dayLabel(for: day, referenceDate: referenceDate, calendar: calendar, dates: dates))
        }
        if let start = task.startTime, let hour = start.hour {
            if let end = task.endTime, let endHour = end.hour {
                when.append(format.range(fromHour: hour, fromMinute: start.minute ?? 0, toHour: endHour, toMinute: end.minute ?? 0)
                    .replacingOccurrences(of: " – ", with: "–"))
            } else {
                when.append(format.time(hour: hour, minute: start.minute ?? 0))
            }
        }
        if !when.isEmpty { parts.append(when.joined(separator: " ")) }
        if let listID = task.listID, let list = lists.first(where: { $0.id == listID }) { parts.append(list.title) }
        if task.priority != .none { parts.append(L10n.tr("paletteaction.priority", "\(String(describing: task.priority.title)) Priority")) }
        if let alert = task.alert { parts.append(L10n.tr("paletteaction.alert", "Alert \(String(describing: alert.title(format: format)))")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

extension SearchIntent {
    /// A date the palette can go to (anything but free text).
    package var isNavigation: Bool {
        if case .freeTextSearch = self { return false }
        return true
    }
}

/// The editable Quick Add fields, prefilled from the parsed draft (Tab).
/// Only what creation needs — no notes, URL or other Task Details.
package struct QuickAddEdit: Equatable {
    package var title: String
    /// nil = the source's default list.
    package var listID: String?
    package var day: Date?
    package var hasTime: Bool
    /// Only the hour and minute are used.
    package var time: Date
    package var priority: TaskPriority
    package var recurrence: TaskRecurrence
    /// A parsed rule the Repeat menu can't express; kept while `recurrence`
    /// still shows it.
    package var customRule: TaskRecurrenceRule?
    package var alert: TaskAlert?

    package init(draft: QuickAddDraft, calendar: Calendar, referenceDate: Date) {
        title = draft.title
        listID = draft.listID
        day = draft.day
        hasTime = draft.startTime?.hour != nil
        let base = draft.day ?? calendar.startOfDay(for: referenceDate)
        time = calendar.date(bySettingHour: draft.startTime?.hour ?? 9, minute: draft.startTime?.minute ?? 0, second: 0, of: base) ?? base
        priority = draft.priority
        recurrence = draft.recurrence?.menuValue ?? .never
        customRule = recurrence.isCustom ? draft.recurrence : nil
        alert = draft.alert
    }

    package var canCreate: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    package func taskDraft(calendar: Calendar) -> TaskDraft {
        var due = day.map { calendar.startOfDay(for: $0) }
        if let day, hasTime {
            let parts = calendar.dateComponents([.hour, .minute], from: time)
            due = calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: day)
        }
        let rule = recurrence.isCustom ? customRule : TaskRecurrenceRule(standard: recurrence)
        return TaskDraft(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines), listID: listID,
            dueDate: due, hasDueTime: due != nil && hasTime, priority: priority,
            recurrenceRule: due == nil ? nil : rule,
            // A time-relative alert needs a due time, as in `TaskItem`.
            alert: alert.flatMap { $0.isRelative && !(due != nil && hasTime) ? nil : $0 }
        )
    }
}

/// Create Event, expanded in place (Tab): the fields an event needs,
/// prefilled from the parsed draft.
package struct EventQuickAddEdit: Equatable {
    package var title: String
    /// nil = the default calendar for new events.
    package var calendarID: String?
    /// Start of the first day.
    package var day: Date
    package var isAllDay: Bool
    /// Timed: the start and end moments (the end may fall on the next day).
    package var start: Date
    package var end: Date
    /// All day: the last day (a span of days).
    package var lastDay: Date
    package var location: String
    package var recurrence: TaskRecurrence
    /// A parsed rule the Repeat menu can't express.
    package var customRule: TaskRecurrenceRule?
    /// Parsed alerts, kept as they are.
    package var alerts: [EventAlert]

    package init(draft: QuickAddDraft, calendar: Calendar, referenceDate: Date) {
        let event = draft.eventDraft(calendar: calendar, referenceDate: referenceDate)
        title = event.title
        calendarID = event.calendarIdentifier
        day = calendar.startOfDay(for: event.start)
        isAllDay = event.isAllDay
        if event.isAllDay {
            start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
            end = calendar.date(byAdding: .minute, value: QuickAddDraft.defaultEventMinutes, to: start) ?? start
            lastDay = calendar.startOfDay(for: event.end)
        } else {
            start = event.start
            end = event.end
            lastDay = day
        }
        location = event.location ?? ""
        recurrence = event.recurrenceRule?.menuValue ?? .never
        customRule = recurrence.isCustom ? event.recurrenceRule : nil
        alerts = event.alerts
    }

    package var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (isAllDay || end > start)
    }

    /// Another day: the times and the length go with it.
    package mutating func move(to newDay: Date, calendar: Calendar) {
        let target = calendar.startOfDay(for: newDay)
        let days = calendar.dateComponents([.day], from: day, to: target).day ?? 0
        guard days != 0 else { return }
        func shift(_ date: Date) -> Date { calendar.date(byAdding: .day, value: days, to: date) ?? date }
        day = target
        start = shift(start)
        end = shift(end)
        lastDay = shift(lastDay)
    }

    /// A new start keeps the length.
    package mutating func setStart(_ newStart: Date) {
        let length = end.timeIntervalSince(start)
        start = newStart
        end = newStart.addingTimeInterval(max(length, 60))
    }

    /// An end at or before the start is on the next day ("22:00–01:00").
    package mutating func setEnd(timeOf time: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        var candidate = calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0,
                                      of: calendar.startOfDay(for: start)) ?? time
        if candidate <= start { candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate }
        end = candidate
    }

    package func eventDraft(calendar: Calendar) -> EventDraft {
        let rule = recurrence.isCustom ? customRule : TaskRecurrenceRule(standard: recurrence)
        let place = location.trimmingCharacters(in: .whitespacesAndNewlines)
        return EventDraft(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            start: isAllDay ? day : start, end: isAllDay ? max(lastDay, day) : end, isAllDay: isAllDay,
            calendarIdentifier: calendarID, location: place.isEmpty ? nil : place,
            recurrenceRule: rule, alerts: alerts
        )
    }
}
