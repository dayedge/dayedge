import AppKit
import SwiftUI
import Domain
import UI
import Agenda
import Tasks
import Intelligence

/// The panel's keys, for both hosts — the popover's `RootView` and the
/// Command Window: what each one does to the shared `RootModels`, and to
/// the few bits of state each root keeps for itself (passed in as bindings).
@MainActor
struct PanelKeyHandler {
    let models: RootModels
    let verticalNavigationRequest: Binding<VerticalNavigationRequest?>
    let taskCompletionRequest: Binding<TaskCompletionRequest?>
    let isSearchFocused: FocusState<Bool>.Binding
    let isSelectorPresented: Binding<Bool>
    /// The Actions list (⌘K) is open — the Command Window's; the popover
    /// has none, so there ⌘K goes on unused.
    let isActionsPresented: Binding<Bool>?
    /// Settings, as the root opens it.
    let openSettings: () -> Void
    /// The Command Window's: Esc with nothing left to close hides it. The
    /// popover has none — there Esc only ever leaves the field.
    var onEscapeAtRoot: (() -> Void)?

    var router: PanelRouter { models.router }
    var agendaNavigation: AgendaNavigationCoordinator { models.agendaNavigation }
    var searchPalette: SearchPaletteModel { models.searchPalette }
    var taskStore: TaskStore { models.taskStore }
    var isAskShown: Bool { router.isAskShown }

    /// Plain arrows reach the calendar only with an empty query and no
    /// Quick Add open (the fields keep their keys), and never in Ask.
    var isArrowNavigationEnabled: Bool {
        router.searchQuery.isEmpty && !searchPalette.isRefining && !isAskShown && isActionsPresented?.wrappedValue != true
    }

    /// ↑ ↓ ↩ for the view: not while searching or in Ask, nor while the
    /// sort menu or the footer selector owns them.
    var isNavigationEnabled: Bool {
        isArrowNavigationEnabled && !taskStore.isSortMenuPresented && !isSelectorPresented.wrappedValue
    }

    func handleArrowKey(_ key: CalendarArrowKey) {
        // Moving on leaves the open details behind: they'd stay on the row
        // that was, while another is selected.
        closeDetails()
        switch key {
        case .up:
            verticalNavigationRequest.wrappedValue = VerticalNavigationRequest(direction: .up)
        case .down:
            verticalNavigationRequest.wrappedValue = VerticalNavigationRequest(direction: .down)
        case .left, .right:
            switch agendaNavigation.selectedViewMode {
            case .month:
                agendaNavigation.moveToAdjacentMonth(key)
            case .day:
                agendaNavigation.moveSelectedDay(by: key == .left ? -1 : 1)
            case .tasks:
                // Lists are landmarks in one document: ← / → jump between them.
                taskStore.moveSection(key == .left ? -1 : 1, query: router.searchQuery)
            case .ask:
                break
            }
        }
    }

    /// Runs a panel shortcut and says whether the key is consumed: false
    /// when a command doesn't apply here, so the key goes on (to the search
    /// field, say); navigation keys and Ask's inert keys are always taken.
    func handleShortcutAction(_ action: PanelAction) -> Bool {
        switch action {
        case .previousDay, .nextDay, .previousWeek, .nextWeek:
            guard agendaNavigation.selectedViewMode != .tasks else { return false }
            closeDetails()
            agendaNavigation.moveSelectedDay(by: action.dayOffset ?? 0)
        case .newEvent, .newTask, .newChat, .showActions, .openSettings:
            return handleAppAction(action)
        case .today:
            agendaNavigation.goToToday()
        case .focusSearch:
            isSearchFocused.wrappedValue = true
            DispatchQueue.main.async {
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
        case .escapeSearch where isAskShown:
            // The app-wide monitor consumes Esc before the composer sees it,
            // so this is the app's one Esc path.
            escapeInAsk()
        case _ where isAskShown:
            // Ask's composer owns the keyboard; DayEdge's keys stay inert but
            // taken, as always (⌘T there would open the font panel).
            break
        case .escapeSearch:
            handleEscape()
        case .openEventDetails, .completeSelectedTask, .openSortMenu:
            return handleSelectionAction(action)
        case .joinSelectedMeeting, .copySelectedMeetingLink, .openSelectedInCalendar, .nextOccurrence, .previousOccurrence:
            return handleSelectedEventAction(action)
        }
        return true
    }

    /// New Event, New Task, New Chat — from any view, Ask included.
    private func handleAppAction(_ action: PanelAction) -> Bool {
        switch action {
        case .newEvent, .newTask:
            isSearchFocused.wrappedValue = true
            router.startCreating(action == .newEvent ? .event : .task)
        case .newChat:
            router.startNewChat()
        case .showActions:
            guard let isActionsPresented else { return false }
            toggleActions(isActionsPresented)
        case .openSettings:
            openSettings()
        default:
            return false
        }
        return true
    }

    /// Esc closes the innermost open thing; with nothing open it clears
    /// the query, then leaves the field (the popover) or closes the window
    /// (the Command Window).
    private func handleEscape() {
        models.noticeCenter.dismissIfPassive()
        let closesInnermost: [() -> Bool] = [
            // The Actions list, back to where focus was.
            { closeActions() },
            // A search result's details closed; the palette stays.
            { searchPalette.dismissResultDetails() || models.searchTasks.dismissDetail() },
            // A #tag's lists and calendars hidden; the query stays.
            { searchPalette.dismissTagCompletion() },
            // Back from the Search view to the palette, query kept.
            { searchPalette.closeResultsView() },
            // Quick Add's date picker closed; Quick Add stays.
            { searchPalette.closeChildEditor() },
            // Quick Add started empty (⌘N, ⇧⌘N): there's no list to fold
            // back into, so it closes.
            { closeEmptyQuickAdd() },
            // Quick Add folded back into the result list.
            { searchPalette.collapse() },
            { closeSelector() },
            { closeSortMenu() },
            // A task detail popover was open and is now closing.
            { taskStore.dismissDetail() },
            // Same, in the agenda or day view.
            { models.calendarTasks.dismissDetail() },
            // A detail popover was open and is now closing.
            { models.eventDetail.dismissPresentedDetails() }
        ]
        // In order: the first that closes something ends Esc.
        guard !closesInnermost.contains(where: { $0() }) else { return }
        switch RootEscape(queryIsEmpty: router.searchQuery.isEmpty, closesWindow: onEscapeAtRoot != nil) {
        case .clearQuery: router.searchQuery = ""
        case .leaveField: isSearchFocused.wrappedValue = false
        case .closeWindow: onEscapeAtRoot?()
        }
    }

    /// Ask's Esc: a pending change denied, else a reply stopped; with
    /// nothing to stop, the Command Window closes, as at the root elsewhere.
    private func escapeInAsk() {
        if models.chat.current?.escape() != true { onEscapeAtRoot?() }
    }

    /// ⌘K. An open details popover closes first — two popovers don't show
    /// at once — and the list opens on its item, once it has gone.
    private func toggleActions(_ isActionsPresented: Binding<Bool>) {
        if isActionsPresented.wrappedValue {
            _ = closeActions()
            return
        }
        guard closeDetails() else {
            isActionsPresented.wrappedValue = true
            return
        }
        DispatchQueue.main.async { isActionsPresented.wrappedValue = true }
    }

    /// Closes any open details popover (a task's or an event's); true if
    /// one was open.
    @discardableResult
    private func closeDetails() -> Bool {
        [taskStore.dismissDetail(), models.calendarTasks.dismissDetail(),
         models.eventDetail.dismissPresentedDetails()].contains(true)
    }

    private func closeActions() -> Bool {
        guard let isActionsPresented, isActionsPresented.wrappedValue else { return false }
        isActionsPresented.wrappedValue = false
        isSearchFocused.wrappedValue = true
        return true
    }

    private func closeEmptyQuickAdd() -> Bool {
        guard searchPalette.isCreatingWithoutQuery, router.searchQuery.isEmpty else { return false }
        searchPalette.clear()
        return true
    }

    private func closeSelector() -> Bool {
        guard isSelectorPresented.wrappedValue else { return false }
        isSelectorPresented.wrappedValue = false
        return true
    }

    private func closeSortMenu() -> Bool {
        guard taskStore.isSortMenuPresented else { return false }
        taskStore.isSortMenuPresented = false
        return true
    }

    /// ↩ details, Space complete: on the Tasks view's selection there, on
    /// the visible calendar view's otherwise. Sort Tasks: the Tasks view only.
    private func handleSelectionAction(_ action: PanelAction) -> Bool {
        let inTasks = agendaNavigation.selectedViewMode == .tasks
        let calendarTasks = models.calendarTasks
        switch action {
        case .openEventDetails where inTasks:
            taskStore.toggleDetailForSelection()
        case .openEventDetails:
            if calendarTasks.selection != nil {
                calendarTasks.openSelectedDetails()
            } else {
                models.eventDetail.openSelectedDetails(isMonthActive: true)
            }
        case .openSortMenu:
            guard inTasks else { return false }
            taskStore.isSortMenuPresented.toggle()
        case .completeSelectedTask:
            if inTasks {
                taskStore.completeSelected()
            } else {
                // The visible calendar view completes its selected task.
                taskCompletionRequest.wrappedValue = TaskCompletionRequest()
            }
        default:
            break
        }
        return true
    }

    /// ⌘J, ⇧⌘C, ⌘O, ⌘] / ⌘[ — on the event selected in Month or Day as it
    /// is now (re-read from the calendar: gone or moved = nothing), and only
    /// what its menu offers (Join needs a link), so a key never does what
    /// the menu wouldn't and never acts on a stale selection.
    private func handleSelectedEventAction(_ action: PanelAction) -> Bool {
        guard let event = selectedEvent,
              let item = models.eventActions.menuActions(for: event).first(where: { $0.shortcut == action }) else { return false }
        models.eventActions.perform(item, for: event)
        return true
    }
}

/// What Esc does once nothing is open: a query is cleared first; then the
/// popover's field is left, and the Command Window closes.
enum RootEscape: Equatable {
    case clearQuery
    case leaveField
    case closeWindow

    init(queryIsEmpty: Bool, closesWindow: Bool) {
        if !queryIsEmpty {
            self = .clearQuery
        } else {
            self = closesWindow ? .closeWindow : .leaveField
        }
    }
}

/// The panel's key monitors, installed once per root: arrows, the view
/// switches and the action shortcuts, all routed to `PanelKeyHandler`.
struct PanelKeyMonitors: ViewModifier {
    let handler: PanelKeyHandler

    func body(content: Content) -> some View {
        content.background {
            // Preserve normal caret navigation once the user has started a
            // search. With an empty query the arrows belong to the calendar.
            ArrowKeyMonitor(isEnabled: handler.isArrowNavigationEnabled, onArrowKey: handler.handleArrowKey)
                .frame(width: 0, height: 0)
            ViewModeShortcutMonitor(onSelect: { handler.models.router.switchView($0) })
                .frame(width: 0, height: 0)
            ActionShortcutMonitor(
                // The sort menu owns ↑ ↓ Return while it is open.
                isNavigationEnabled: handler.isNavigationEnabled,
                onAction: handler.handleShortcutAction
            )
            .frame(width: 0, height: 0)
        }
    }
}

private extension PanelAction {
    /// How far a day shortcut moves the selected day.
    var dayOffset: Int? {
        switch self {
        case .previousDay: -1
        case .nextDay: 1
        case .previousWeek: -7
        case .nextWeek: 7
        default: nil
        }
    }
}
