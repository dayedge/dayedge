import Foundation
import Observation
import Domain
import UI

extension SearchPaletteModel {
    // MARK: - Keyboard contract

    /// A click on an action row.
    package func select(_ kind: PaletteAction.Kind) {
        guard !isRefining, selectableItems.contains(.action(kind)) else { return }
        chosen = .action(kind)
    }

    /// A click on a preview result.
    package func selectResult(_ id: String) {
        guard !isRefining, results.preview.contains(where: { $0.id == id }) else { return }
        chosen = .result(id)
    }

    /// ↑ / ↓ through the enabled actions and Search's preview results
    /// (placeholders are skipped). A result that left the preview counts
    /// as Search.
    package func moveSelection(_ delta: Int) {
        guard !isRefining else { return }
        if isResultsViewShown {
            results.select(delta)
            return
        }
        let items = selectableItems
        guard !items.isEmpty else { return }
        let current = selection.flatMap { items.firstIndex(of: $0) } ?? 0
        chosen = items[min(max(current + delta, 0), items.count - 1)]
    }

    /// Tab: expands the selected action if it can be refined. Returns
    /// whether it did.
    @discardableResult
    package func refine() -> Bool {
        if isResultsViewShown {
            guard let item = results.selectedRowItem else { return true }
            onShowResult(item)
            return true
        }
        if !isRefining, selectedKind == .search {
            openResultsView()
            return isResultsViewShown
        }
        if !isRefining, let selectedResult {
            onShowResult(selectedResult)
            return true
        }
        guard !isRefining, let action = selectedAction, action.supportsRefinement, let taskDraft else { return false }
        // Expanding again picks up the fields as they were left.
        switch action.kind {
        case .createTask: edit = edit ?? QuickAddEdit(draft: taskDraft, calendar: calendar, referenceDate: now())
        case .createEvent: eventEdit = eventEdit ?? EventQuickAddEdit(draft: taskDraft, calendar: calendar, referenceDate: now())
        default: return false
        }
        isRefining = true
        return true
    }

    /// Esc with the date picker open: close just that. Returns whether it
    /// did.
    @discardableResult
    package func closeChildEditor() -> Bool {
        guard isChildEditorOpen else { return false }
        openChildEditor = nil
        return true
    }

    /// Esc while refining: back to the list. Returns whether it collapsed.
    /// The fields stay as edited — expanding again, or Return here, uses them
    /// (a new query starts over).
    @discardableResult
    package func collapse() -> Bool {
        guard isRefining, !isCommitting else { return false }
        isRefining = false
        return true
    }

    /// Return in the query field: runs the selection collapsed; expanded,
    /// the query is already parsed as typed, and Return never creates.
    package func submitQuery() {
        guard !isRefining else { return }
        executeSelected()
    }

    /// ⌘Return: create, from wherever focus is — an open picker is closed
    /// first (its value is already in the fields).
    package func createFromKeyboard() {
        openChildEditor = nil
        executeSelected()
    }

    // swiftlint:disable cyclomatic_complexity - one case per palette action
    /// Runs the selected action (Return collapsed, ⌘Return, a click): a
    /// create uses the edited fields when there are any, else the parsed
    /// query. Nothing selected (only placeholders) → nothing.
    package func executeSelected() {
        if isResultsViewShown {
            if let item = results.selectedRowItem { openDetails(item) }
            return
        }
        if let selectedResult, !isRefining {
            openDetails(selectedResult)
            return
        }
        guard let action = selectedAction, action.isEnabled, !isCommitting, !isChildEditorOpen else { return }
        switch action.kind {
        case .goToDate:
            guard let dateIntent else { return }
            onGoToDate(dateIntent)
            clear()
        case .createTask:
            let draft: TaskDraft
            if let edit {
                guard edit.canCreate else { return }
                draft = edit.taskDraft(calendar: calendar)
            } else if let taskDraft {
                draft = taskDraft.taskDraft(calendar: calendar)
            } else { return }
            commit(draft)
        case .createEvent:
            if let eventEdit {
                guard eventEdit.canCreate else { return }
                commit(eventEdit.eventDraft(calendar: calendar))
            } else if let taskDraft {
                commit(taskDraft.eventDraft(calendar: calendar, referenceDate: now()))
            }
        case .askAI:
            onAsk(query)
        case .search:
            return // Tab opens the detailed results; Return has no action here
        }
    }
    // swiftlint:enable cyclomatic_complexity

    /// A result's details: the same bubbles as the agenda's.
    package func openDetails(_ item: SearchResultRowItem) {
        switch item.result {
        case .event(let event):
            eventDetailRequest = EventDetailPresentationRequest(eventID: event.id, action: .toggle)
        case .task(let task):
            onOpenTaskResult(task, item.day ?? calendar.startOfDay(for: now()))
        }
    }

    /// Reported by a preview event row.
    package func eventDetailPresentationChanged(eventID: String, isShowing: Bool) {
        if isShowing {
            presentedEventID = eventID
        } else if presentedEventID == eventID {
            presentedEventID = nil
        }
    }

    /// Esc with a result's event details open: close them. Returns whether
    /// it did.
    @discardableResult
    package func dismissResultDetails() -> Bool {
        guard let presentedEventID else { return false }
        eventDetailRequest = EventDetailPresentationRequest(eventID: presentedEventID, action: .dismiss)
        return true
    }

    /// Saves first; only a saved task moves on (the palette resolves away
    /// into it). A failure leaves everything as it was — values included.
    private func commit(_ draft: TaskDraft) {
        isCommitting = true
        let beat = commitBeat
        creation = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let item = try await createTask(draft)
                try? await Task.sleep(for: beat)
                onTaskCreated(item)
                clear()
            } catch {
                isCommitting = false
            }
        }
    }

    /// The same for an event: saved first, then the palette goes.
    private func commit(_ draft: EventDraft) {
        isCommitting = true
        let beat = commitBeat
        creation = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await createEvent(draft)
                try? await Task.sleep(for: beat)
                onEventCreated(snapshot)
                clear()
            } catch {
                isCommitting = false
            }
        }
    }
}
