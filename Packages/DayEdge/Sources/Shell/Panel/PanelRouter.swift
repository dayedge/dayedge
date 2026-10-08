import AppKit
import Foundation
import Observation
import SwiftUI
import Domain
import UI
import Agenda
import Tasks
import Intelligence

/// The panel's search query and every route between its features: view
/// changes, search intents and results, Quick Add, Search → Ask, a date
/// in a chat answer, and the status menu's commands. Each of them leaves
/// the search field in a defined state, so they live together.
@MainActor
@Observable
final class PanelRouter {
    var searchQuery = ""
    /// Mirrors the view's Reduce Motion setting (Quick Add's arrival).
    @ObservationIgnored var reduceMotion = false

    @ObservationIgnored private let agendaNavigation: AgendaNavigationCoordinator
    @ObservationIgnored private let taskStore: TaskStore
    @ObservationIgnored private let searchPalette: SearchPaletteModel
    @ObservationIgnored private let chat: ChatCoordinator

    init(agendaNavigation: AgendaNavigationCoordinator, taskStore: TaskStore,
         searchPalette: SearchPaletteModel, chat: ChatCoordinator) {
        self.agendaNavigation = agendaNavigation
        self.taskStore = taskStore
        self.searchPalette = searchPalette
        self.chat = chat
    }

    var isSearchExpanded: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Ask is the view on screen.
    var isAskShown: Bool { agendaNavigation.displayedViewMode == .ask }

    /// Every view change goes through here: Ask needs its conversation to
    /// exist before it's shown.
    func selectViewMode(_ mode: ViewMode) {
        // Picking a view leaves the Search view (and its query).
        if searchPalette.isResultsViewShown { searchQuery = "" }
        if mode == .ask { chat.ensureConversation() }
        agendaNavigation.selectViewMode(mode)
    }

    /// A date in a chat answer opens that day in the calendar.
    func showDay(_ day: Date) {
        agendaNavigation.selectDate(Calendar.autoupdatingCurrent.startOfDay(for: day), preparingMonthAgenda: true)
        selectViewMode(.day)
    }

    /// A fresh open lands on the preferred view (Settings → General);
    /// otherwise only "now" catches up.
    func handleOpenRequest(_ request: PopoverOpenRequest) {
        switch request.behavior {
        case .todayNow:
            selectViewMode(GeneralSettings.defaultView())
            agendaNavigation.requestTodayNow(at: request.openedAt, animated: false)
        case .preserve:
            agendaNavigation.refreshNowPresentation(at: request.openedAt)
        }
    }

    /// The status menu's quick actions, run once the popover is on screen.
    /// `focusSearch` focuses the field (focus belongs to the view).
    func perform(_ command: PopoverCommand, focusSearch: () -> Void) async {
        switch command {
        case .search:
            // Search lives over the calendar views, not the app.
            if isAskShown {
                let preferred = GeneralSettings.defaultView()
                selectViewMode(preferred == .ask ? .month : preferred)
            }
            focusSearch()
        case .ask:
            selectViewMode(.ask)
        case .showEvent(let target):
            selectViewMode(.day)
            await agendaNavigation.navigateToOccurrence(target)
        case .showTodayTasks:
            selectViewMode(.tasks)
        }
    }

    func handle(_ intent: SearchIntent) {
        let calendar = Calendar.autoupdatingCurrent
        switch intent {
        case .jumpToDate(let date):
            if calendar.isDateInToday(date) {
                agendaNavigation.goToToday()
                searchQuery = ""
                return
            }
            let day = calendar.startOfDay(for: date)
            agendaNavigation.selectMonthImmediately()
            agendaNavigation.selectDate(day, preparingMonthAgenda: true)

        case .jumpToMonth(let date):
            agendaNavigation.jumpToMonth(date)

        case .freeTextSearch:
            // Full-text event search is a separate, later piece of work —
            // nothing to route to yet.
            break
        }
        searchQuery = ""
    }

    /// Search → Ask: always a new chat, already asked. The
    /// conversation is seeded before the view switches, so the app's very
    /// first frame already shows the question and its pending answer —
    /// nothing expands or animates into place. The
    /// previous chat moves to the history; the search field is cleared.
    func ask(_ query: String) {
        let session = chat.makeSession()
        session.start(with: query)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            chat.start(session)
            searchQuery = ""
            agendaNavigation.selectViewMode(.ask)
        }
    }

    /// Quick Add → the task's natural home: the palette resolves away, the
    /// Tasks view comes in, and the new task is revealed in its section,
    /// selected (Space, Return and ↑ / ↓ work on it at once) and briefly
    /// emphasized as it arrives. Runs only after the save succeeded.
    func showCreatedTask(_ item: TaskItem) {
        withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.17)) { searchQuery = "" }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.05 : 0.12)) { [self] in
            withAnimation(.easeInOut(duration: 0.22)) { agendaNavigation.selectViewMode(.tasks) }
            if taskStore.reveal(item.id) { taskStore.markArrival(item.id) }
        }
    }

    /// Tab on a search result: an event in the Month agenda on its day,
    /// selected; a task in Tasks, revealed and selected.
    func showSearchResult(_ item: SearchResultRowItem) {
        switch item.result {
        case .event(let event):
            guard let start = event.startDate else { return }
            searchQuery = ""
            agendaNavigation.selectViewMode(.month)
            Task { await agendaNavigation.navigateToOccurrence(OccurrenceNavigationTarget(eventID: event.id, startDate: start)) }
        case .task(let task):
            taskStore.actions.showInTasks(task)
        }
    }

    /// Calendar → Tasks: the task itself, selected, in a document not
    /// filtered by a search left over from before.
    func revealInTasks(_ taskID: String) -> Bool {
        guard taskStore.tasks.contains(where: { $0.id == taskID }) else { return false }
        searchQuery = ""
        agendaNavigation.selectViewMode(.tasks)
        return taskStore.reveal(taskID)
    }

    /// The palette's and the task actions' routes come back here.
    func connect(eventActions: EventActionCoordinator, searchTaskCoordinator: CalendarTaskCoordinator) {
        let palette = searchPalette
        palette.onGoToDate = { [weak self] in self?.handle($0) }
        palette.createTask = { [taskStore] draft in try await taskStore.actions.create(draft) }
        palette.onTaskCreated = { [weak self] in self?.showCreatedTask($0) }
        palette.createEvent = { [eventActions] draft in try await eventActions.create(draft) }
        palette.onEventCreated = { [weak self] event in self?.handle(.jumpToDate(event.start)) }
        palette.eventCalendars = { [eventActions] in
            await eventActions.writableCalendars().map { CalendarSource(id: $0.identifier, title: $0.title, tint: $0.tint) }
        }
        palette.onOpenTaskResult = { [searchTaskCoordinator] task, day in
            searchTaskCoordinator.toggleDetail(for: .init(taskID: task.id, day: day))
        }
        palette.onShowResult = { [weak self] in self?.showSearchResult($0) }
        palette.onAsk = { [weak self] in self?.ask($0) }
        // Only where a new reminder can actually go.
        palette.taskLists = { [taskStore] in
            let repository = taskStore.repository
            guard repository.accessStatus == .granted else { return [] }
            return repository.lists.filter { $0.allowsModifications && repository.listVisibility.isEnabled($0.id) }
        }
        taskStore.actions.revealInTasks = { [weak self] in self?.revealInTasks($0) ?? false }
        taskStore.actions.navigate = { [agendaNavigation] taskID, day, showingCalendar in
            // From the Tasks view, the calendar takes over; inside the
            // calendar, Month or Day stays as it is.
            if showingCalendar { agendaNavigation.selectViewMode(.month) }
            Task { await agendaNavigation.navigateToTask(taskID, on: day) }
        }
    }
}
