import Foundation
import Domain

/// One row of the search palette. Precedence is deterministic — a date
/// alone → "Go to"; else TimeWhisper candidates → "Create"; then Search
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
    /// What the query was understood as ("Friday, 2 Oct · 10:00 · Work").
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
    package static func build(dateIntent: SearchIntent?, candidates: [QuickAddCandidate], lists: [CalendarSource],
                              calendars: [CalendarSource] = [], conflict: EventConflict? = nil,
                              isSearchable: Bool = true, referenceDate: Date, calendar: Calendar,
                              format: TimeFormat = .twentyFourHour, dates: DatePresentationFormatter = .current) -> [PaletteAction] {
        var actions: [PaletteAction] = []
        if let dateIntent {
            let title = SearchSuggestion.title(for: dateIntent, referenceDate: referenceDate, calendar: calendar, dates: dates)
            actions.append(PaletteAction(kind: .goToDate, title: title, subtitle: nil, isEnabled: true,
                                         supportsRefinement: false, accessibilityLabel: title))
        } else {
            let offered = candidates.filter { candidate in
                switch candidate {
                case .task: !lists.isEmpty
                case .event: !calendars.isEmpty
                }
            }
            // Both offered: each says what it makes.
            let isChoice = offered.count > 1
            for candidate in offered {
                switch candidate {
                case .task(let task):
                    actions.append(PaletteAction(
                        kind: .createTask, title: isChoice ? L10n.tr(
                            "paletteaction.create.task", "Create task “\(String(describing: task.title))”"
                        ) : L10n.tr(
                            "paletteaction.create.618d1a", "Create “\(String(describing: task.title))”"
                        ),
                        subtitle: summary(of: task, lists: lists, referenceDate: referenceDate, calendar: calendar, format: format, dates: dates),
                        isEnabled: true, supportsRefinement: true, accessibilityLabel: L10n.tr("paletteaction.create.task.cc3d84", "Create task, \(String(describing: task.title))")
                    ))
                case .event(let event):
                    actions.append(PaletteAction(
                        kind: .createEvent, title: L10n.tr("paletteaction.create.event", "Create event “\(String(describing: event.title))”"),
                        subtitle: summary(of: event, recurrence: event.recurrenceRule, calendars: calendars,
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
            let last = calendar.date(byAdding: .day, value: -1, to: event.end) ?? event.start
            if !calendar.isDate(last, inSameDayAs: event.start) { when += " – " + day(last) }
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
        if let alert = event.alerts.first {
            parts.append(L10n.tr("paletteaction.alert", "Alert \(String(describing: alert.title(isAllDay: event.isAllDay, format: format, dates: dates)))"))
        }
        return parts.joined(separator: " · ")
    }

    /// What was understood, and only that — one compact line beside the
    /// title: "Friday, 2 Oct 10:00 · Work", "Every Friday 17:00 · Work ·
    /// High Priority" (when and its time read as one block). nil when there
    /// is nothing beyond the title.
    package static func summary(of task: TaskDraft, lists: [CalendarSource], referenceDate: Date, calendar: Calendar,
                                format: TimeFormat = .twentyFourHour, dates: DatePresentationFormatter = .current) -> String? {
        var parts: [String] = []
        var when: [String] = []
        if let rule = task.recurrenceRule {
            when.append(rule.summary)
        } else if let day = task.dueDate {
            when.append(SearchSuggestion.dayLabel(for: day, referenceDate: referenceDate, calendar: calendar, dates: dates))
        }
        if task.hasDueTime, let due = task.dueDate {
            when.append(format.time(due, calendar: calendar))
        }
        if !when.isEmpty { parts.append(when.joined(separator: " ")) }
        if let listID = task.listID, let list = lists.first(where: { $0.id == listID }) { parts.append(list.title) }
        if task.priority != .none { parts.append(L10n.tr("paletteaction.priority", "\(String(describing: task.priority.title)) Priority")) }
        if let alert = task.alert { parts.append(L10n.tr("paletteaction.alert", "Alert \(String(describing: alert.title(format: format)))")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
