import Foundation
import Observation
import Domain
import UI

/// The search palette's state and behavior; `SearchBarView` only draws it.
/// One keyboard contract everywhere:
///   ↑ / ↓  choose an (enabled) action, or one of Search's preview results
///   Enter  run the selected action; on a result, open its details
///   Tab    refine the selected action in place (Quick Add), if it can be;
///          on a result, show it in Calendar / Tasks
///   Esc    collapse a refinement (the root handles closing the palette)
/// Precedence is fixed: the strict date parser (the search pipeline,
/// unchanged) first; only if it says no, the Quick Add task parser.
@MainActor
@Observable
package final class SearchPaletteModel {
    /// What ↑ / ↓ lands on: an action, or a Search preview result.
    package enum Selection: Equatable {
        case action(PaletteAction.Kind)
        case result(String)
    }

    package internal(set) var actions: [PaletteAction] = []
    /// What was chosen (by default, ↑ / ↓ or a click); `selection` is
    /// what's in effect once Search's rows come and go with its results.
    var chosen: Selection?
    package var selection: Selection? {
        let items = selectableItems
        if let chosen, items.contains(chosen) { return chosen }
        // A result that left the preview falls back to Search.
        if case .result = chosen, items.contains(.action(.search)) { return .action(.search) }
        return items.first
    }
    package var selectedKind: PaletteAction.Kind? {
        if case .action(let kind) = selection { return kind }
        return nil
    }
    /// The preview result selected, if one is (and still shown).
    package var selectedResult: SearchResultRowItem? {
        guard case .result(let id) = selection else { return nil }
        return results.preview.first { $0.id == id }
    }
    /// The detailed Search view replaces the calendar below the field;
    /// while it shows, ↑ / ↓, Return and Tab work its results.
    package var isResultsViewShown = false
    /// Asks a preview event row to open / close its details.
    package internal(set) var eventDetailRequest: EventDetailPresentationRequest?
    /// The preview event whose details are showing.
    package internal(set) var presentedEventID: String?
    /// Quick Add is expanded in place.
    package internal(set) var isRefining = false
    /// The Quick Add fields as last edited — kept through a collapse, cleared
    /// by a new query.
    package var edit: QuickAddEdit?
    /// Create Event's fields, likewise; each change re-checks what its time
    /// runs into.
    package var eventEdit: EventQuickAddEdit? {
        didSet { if eventEdit != oldValue { checkEditOverlap() } }
    }
    /// The meeting the edited event's time runs into (first occurrence).
    package internal(set) var editOverlap: EventOverlap?
    /// Calendars a new event can go to, as of the last resolution.
    package internal(set) var eventCalendarOptions: [CalendarSource] = []
    @ObservationIgnored var overlapCheck: Task<Void, Never>?
    /// The Quick Add field whose child editor (choice list, date or time
    /// picker) is open. That editor owns ↑ / ↓, Return and Esc.
    package var openChildEditor: QuickAddField?
    package var isChildEditorOpen: Bool { openChildEditor != nil }
    /// Creating: the task is being saved (Quick Add stays, inert, until it
    /// is — and stays editable if saving fails).
    package internal(set) var isCommitting = false
    /// Events and tasks matching the query — Search's counts and preview.
    package let results = SearchSession()

    // Resolved payloads for the actions.
    @ObservationIgnored var dateIntent: SearchIntent?
    @ObservationIgnored var taskDraft: QuickAddDraft?
    /// The trimmed query the actions were built for — what Ask asks.
    @ObservationIgnored var query = ""
    @ObservationIgnored var resolution: Task<Void, Never>?
    @ObservationIgnored var creation: Task<Void, Never>?
    @ObservationIgnored var generation = 0

    @ObservationIgnored package let resolveDate: (String, Date, Calendar) async -> SearchIntent
    /// Text, now, calendar, task lists, event calendars → the parsed draft.
    @ObservationIgnored package let resolveTask: (String, Date, Calendar, [CalendarSource], [CalendarSource]) async -> QuickAddDraft?
    /// Lists a new task can go to (writable, not excluded); empty = no
    /// task creation (e.g. no Reminders access).
    @ObservationIgnored package var taskLists: () -> [CalendarSource] = { [] }
    /// Calendars a new event can go to (writable); empty = no event
    /// creation (e.g. no Calendar access).
    @ObservationIgnored package var eventCalendars: () async -> [CalendarSource] = { [] }
    /// Saves the event; throws (having told the user) when it can't.
    @ObservationIgnored package var createEvent: (EventDraft) async throws -> EventSnapshot = { _ in throw EventEditError.notWritable }
    /// The events of a day, to say whether a new event's time is free.
    @ObservationIgnored package var eventsOn: (Date) async -> [AgendaEventModel] = { _ in [] }
    /// The saved event — the palette goes, its day shows.
    @ObservationIgnored package var onEventCreated: (EventSnapshot) -> Void = { _ in }
    @ObservationIgnored package var onGoToDate: (SearchIntent) -> Void = { _ in }
    /// Ask: the query becomes the first message of a conversation.
    @ObservationIgnored package var onAsk: (String) -> Void = { _ in }
    /// Saves the task; throws (having told the user) when it can't.
    @ObservationIgnored package var createTask: (TaskDraft) async throws -> TaskItem = { _ in throw TaskSourceError.unsupported }
    /// The saved task — where the "this draft became that task" transition
    /// starts.
    @ObservationIgnored package var onTaskCreated: (TaskItem) -> Void = { _ in }
    /// Return on a result: its task details (events open in place).
    @ObservationIgnored package var onOpenTaskResult: (TaskItem, Date) -> Void = { _, _ in }
    /// Tab on a result: Show in Calendar / Show in Tasks.
    @ObservationIgnored package var onShowResult: (SearchResultRowItem) -> Void = { _ in }

    /// Tab (or a click) on Search: the detailed Search view.
    package func openResultsView() {
        guard isSearchSelectable else { return }
        isResultsViewShown = true
    }

    /// Esc in the Search view: back to the palette, the query kept.
    @discardableResult
    package func closeResultsView() -> Bool {
        guard isResultsViewShown else { return false }
        isResultsViewShown = false
        return true
    }
    /// The brief beat between Return and the palette resolving away.
    @ObservationIgnored package var commitBeat: Duration = .milliseconds(80)
    @ObservationIgnored package var calendar: Calendar = .autoupdatingCurrent
    @ObservationIgnored package var now: () -> Date = { Date() }
    @ObservationIgnored package var dates: () -> DatePresentationFormatter = { .current }
    @ObservationIgnored package var timeFormat: () -> TimeFormat = { .current }

    package init(
        resolveDate: @escaping (String, Date, Calendar) async -> SearchIntent = { text, date, calendar in
            await SearchIntentPipeline.live.resolve(text, referenceDate: date, calendar: calendar)
        },
        resolveTask: @escaping (String, Date, Calendar, [CalendarSource], [CalendarSource]) async -> QuickAddDraft? = { text, date, calendar, lists, calendars in
            let options = lists.map { QuickAddList(id: $0.id, title: $0.title) }
            let calendarOptions = calendars.map { QuickAddList(id: $0.id, title: $0.title) }
            return await TaskQuickAddStage(lists: { options }, calendars: { calendarOptions })
                .resolve(text, referenceDate: date, calendar: calendar)
        }
    ) {
        self.resolveDate = resolveDate
        self.resolveTask = resolveTask
    }

    package var selectedAction: PaletteAction? { actions.first { $0.kind == selectedKind } }

    /// Go to / Create: an interpretation the query can run besides Search.
    private var hasOtherInterpretation: Bool {
        actions.contains { [.goToDate, .createTask, .createEvent].contains($0.kind) && $0.isEnabled }
    }

    /// Search is listed when it found something — or, with nothing else to
    /// run, as a quiet "No matches" (it gives way to Go to / Create).
    package var isSearchShown: Bool {
        // Under three letters there's nothing to search yet: no row at all.
        guard actions.contains(where: { $0.kind == .search && $0.isEnabled }) else { return false }
        return results.total > 0 || !hasOtherInterpretation
    }

    /// Selectable only with results to show.
    package var isSearchSelectable: Bool {
        isSearchShown && results.total > 0 && actions.contains { $0.kind == .search && $0.isEnabled }
    }

    /// ↑ / ↓ order: enabled actions, Search's preview results right after
    /// Search.
    package var selectableItems: [Selection] {
        actions.filter(\.isEnabled).flatMap { action -> [Selection] in
            guard action.kind == .search else { return [.action(action.kind)] }
            return isSearchSelectable ? [.action(.search)] + results.preview.map { .result($0.id) } : []
        }
    }

    /// What is shown: the alternatives disappear once the task is being
    /// refined — Esc brings them back.
    package var visibleActions: [PaletteAction] {
        if isRefining { return actions.filter { $0.kind == (eventEdit != nil ? .createEvent : .createTask) } }
        return actions.filter { $0.kind != .search || isSearchShown }
    }

    /// The footer's key hints for the current state.
    package var keyHints: [PaletteKeyHint] {
        if isResultsViewShown {
            let back = PaletteKeyHint(key: .escape, label: L10n.tr("palette.back", "Back"))
            return (results.selectedRowItem.map(PaletteActions.hints(for:)) ?? []) + [back]
        }
        if let selectedResult { return PaletteActions.hints(for: selectedResult) }
        return PaletteActions.hints(for: selectedAction, isRefining: isRefining)
    }
}
