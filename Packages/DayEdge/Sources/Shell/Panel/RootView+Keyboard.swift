import AppKit
import SwiftUI
import UI

extension RootView {
    func handleArrowKey(_ key: CalendarArrowKey) {
        switch key {
        case .up:
            verticalNavigationRequest = VerticalNavigationRequest(direction: .up)
        case .down:
            verticalNavigationRequest = VerticalNavigationRequest(direction: .down)
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
    func handleShortcutAction(_ action: KeyboardCommandAction) -> Bool {
        switch action {
        case .previousDay, .nextDay, .previousWeek, .nextWeek:
            guard agendaNavigation.selectedViewMode != .tasks else { return false }
            agendaNavigation.moveSelectedDay(by: action.dayOffset ?? 0)
        case .today:
            agendaNavigation.goToToday()
        case .focusSearch:
            isSearchFocused = true
            DispatchQueue.main.async {
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
        case .escapeSearch where isAskShown:
            // The app-wide monitor consumes Esc before the composer sees it,
            // so this is the app's one Esc path.
            models.chat.current?.escape()
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

    /// Esc closes the innermost open thing; with nothing open it clears
    /// the query, then leaves the field.
    private func handleEscape() {
        models.noticeCenter.dismissIfPassive()
        let closesInnermost: [() -> Bool] = [
            // A search result's details closed; the palette stays.
            { searchPalette.dismissResultDetails() || models.searchTasks.dismissDetail() },
            // Back from the Search view to the palette, query kept.
            { searchPalette.closeResultsView() },
            // Quick Add's date picker closed; Quick Add stays.
            { searchPalette.closeChildEditor() },
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
        if router.searchQuery.isEmpty {
            isSearchFocused = false
        } else {
            router.searchQuery = ""
        }
    }

    private func closeSelector() -> Bool {
        guard isSelectorPresented else { return false }
        isSelectorPresented = false
        return true
    }

    private func closeSortMenu() -> Bool {
        guard taskStore.isSortMenuPresented else { return false }
        taskStore.isSortMenuPresented = false
        return true
    }

    /// ↩ details, Space complete: on the Tasks view's selection there, on
    /// the visible calendar view's otherwise. Sort Tasks: the Tasks view only.
    private func handleSelectionAction(_ action: KeyboardCommandAction) -> Bool {
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
                taskCompletionRequest = TaskCompletionRequest()
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
    private func handleSelectedEventAction(_ action: KeyboardCommandAction) -> Bool {
        guard agendaNavigation.selectedViewMode == .month || agendaNavigation.selectedViewMode == .day,
              let selection = models.eventDetail.keyboardSelectedEvent,
              let event = selection.current(in: models.dataProvider.events(for: selection.date, calendar: .autoupdatingCurrent)),
              let item = models.eventActions.menuActions(for: event).first(where: { $0.shortcut == action }) else { return false }
        models.eventActions.perform(item, for: event)
        return true
    }
}

private extension KeyboardCommandAction {
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
