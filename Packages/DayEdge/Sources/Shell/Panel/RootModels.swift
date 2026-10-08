import EventKit
import Foundation
import Domain
import Platform
import UI
import Agenda
import Tasks
import Intelligence

/// The panel's object graph, built once and wired here, so `RootView`
/// only presents it. A plain container: views observe the objects
/// inside, never this.
///
/// `eventStore`/`dataProvider`/`visibilityStore` are constructed once
/// by `AppDelegate` and passed in, rather than each built fresh here —
/// `AppDelegate` needs the same `dataProvider` itself, to compute
/// the menu-bar status item's "remaining events today" count before
/// the panel has ever been shown (see `AppDelegate.refreshBadge`).
/// Owning a second, independent `CalendarProvider` there would mean
/// two readers and two change observers for the same data.
@MainActor
final class RootModels {
    let viewModel: CalendarViewModel
    /// Deliberately a separate `@Observable` object from `viewModel` — see
    /// `AgendaSectionStore`'s doc comment for why that's what actually
    /// fixes the click/switch-view lag, not just an organizational choice.
    let agendaStore: AgendaSectionStore
    /// View-mode selection and date/agenda navigation — see its own doc
    /// comment for why it needs `viewModel`/`agendaStore` handed in as
    /// stable references.
    let agendaNavigation: AgendaNavigationCoordinator
    /// Keyboard-driven event selection and the event-detail popover's own
    /// presentation/focus/action state — a distinct `@Observable` object
    /// for the same reason `AgendaSectionStore` is: isolates this state's
    /// own re-render scope from everything else the root view reads.
    let eventDetail: EventDetailCoordinator
    /// Right-click event-menu actions (Join, Copy Link, Open in Apple
    /// Calendar, Maps, cancelled-event removal) — one instance, read by
    /// every event view through the environment rather than threaded
    /// down explicitly (see `EventActionEnvironment.swift`).
    let eventActions: EventActionCoordinator
    let noticeCenter: NoticeCenter
    let taskStore: TaskStore
    /// Task selection/details inside the agenda and day view.
    let calendarTasks: CalendarTaskCoordinator
    /// Chat's own task-details presentation, apart from the calendar's.
    let chatTasks: CalendarTaskCoordinator
    /// Search results' task details — their own, like chat's.
    let searchTasks: CalendarTaskCoordinator
    /// The search palette: Go to a date, Create a task, Ask, Search.
    let searchPalette: SearchPaletteModel
    let chat: ChatCoordinator
    let router: PanelRouter
    let refresh: PanelRefreshCoordinator
    let daySnapshot: DaySnapshot
    let workdayStore = WorkdayStore(provider: CachingHolidayProvider.shared)
    let visibilityStore: SourceVisibilityStore
    /// The calendar as it is now — what keyboard commands re-check a
    /// selection against.
    let dataProvider: CalendarDataProviding
    let reminderSuppression: ReminderSuppressionStore
    let assistantSettings: AssistantSettingsStore
    let presentationCoordinator: PopoverPresentationCoordinator
    let calendarAccess: CalendarPermissionMonitor

    init(eventStore: EKEventStore,
         dataProvider: CalendarDataProviding,
         visibilityStore: SourceVisibilityStore,
         taskRepository: TaskRepository,
         reminderSuppression: ReminderSuppressionStore,
         assistantSettings: AssistantSettingsStore,
         presentationCoordinator: PopoverPresentationCoordinator,
         calendarAccess: CalendarPermissionMonitor) {
        self.visibilityStore = visibilityStore
        self.dataProvider = dataProvider
        self.calendarAccess = calendarAccess
        self.reminderSuppression = reminderSuppression
        self.assistantSettings = assistantSettings
        self.presentationCoordinator = presentationCoordinator

        let today = Calendar.current.startOfDay(for: .now)
        // Same first weekday as the month grid (see `GeneralSettings`).
        var agendaCalendar = Calendar.autoupdatingCurrent
        agendaCalendar.firstWeekday = GeneralSettings.weekStart().firstWeekday()

        let viewModel = CalendarViewModel(dataProvider: dataProvider, visibleMonth: today, selectedDate: today)
        let agendaStore = AgendaSectionStore(dataProvider: dataProvider, calendar: agendaCalendar)
        let eventDetail = EventDetailCoordinator()
        let agendaNavigation = AgendaNavigationCoordinator(
            viewModel: viewModel, agendaStore: agendaStore, presentationCoordinator: presentationCoordinator,
            onWillChangeDate: { [eventDetail] in eventDetail.clearKeyboardSelection() }
        )
        agendaNavigation.timedTasks = { [taskRepository] day in
            guard TaskSettings.showsInCalendar() else { return [] }
            return taskRepository.scheduledIndex().tasks(on: day).timed
        }
        self.viewModel = viewModel
        self.agendaStore = agendaStore
        self.eventDetail = eventDetail
        self.agendaNavigation = agendaNavigation

        let noticeCenter = NoticeCenter()
        taskRepository.noticeCenter = noticeCenter
        let taskStore = TaskStore(repository: taskRepository)
        self.noticeCenter = noticeCenter
        self.taskStore = taskStore
        self.calendarTasks = CalendarTaskCoordinator(actions: taskStore.actions)
        self.chatTasks = CalendarTaskCoordinator(actions: taskStore.actions)
        self.searchTasks = CalendarTaskCoordinator(actions: taskStore.actions)

        // One event editor for the popover, its menu and the app chat.
        let eventEditor = EventKitEventEditor(eventStore: eventStore)
        self.eventActions = Self.makeEventActions(eventStore: eventStore, editor: eventEditor, noticeCenter: noticeCenter,
                                                  reminderSuppression: reminderSuppression, agendaNavigation: agendaNavigation)
        self.chat = Self.makeChat(settings: assistantSettings, dataProvider: dataProvider, calendar: agendaCalendar,
                                  taskRepository: taskRepository, eventEditor: eventEditor)

        self.searchPalette = Self.makeSearchPalette(dataProvider: dataProvider, calendar: agendaCalendar, taskStore: taskStore)
        self.router = PanelRouter(agendaNavigation: agendaNavigation, taskStore: taskStore,
                                  searchPalette: searchPalette, chat: chat)
        router.connect(eventActions: eventActions, searchTaskCoordinator: searchTasks)

        self.refresh = PanelRefreshCoordinator(
            eventStore: eventStore, viewModel: viewModel, agendaStore: agendaStore,
            visibilityStore: visibilityStore, agendaNavigation: agendaNavigation,
            searchPalette: searchPalette, taskStore: taskStore, noticeCenter: noticeCenter,
            reminderSuppression: reminderSuppression, presentationCoordinator: presentationCoordinator,
            calendarAccess: calendarAccess, eventDetail: eventDetail
        )
        self.daySnapshot = DaySnapshot(viewModel: viewModel, agendaStore: agendaStore, agendaNavigation: agendaNavigation)
    }

    private static func makeEventActions(eventStore: EKEventStore, editor: EventKitEventEditor, noticeCenter: NoticeCenter,
                                         reminderSuppression: ReminderSuppressionStore,
                                         agendaNavigation: AgendaNavigationCoordinator) -> EventActionCoordinator {
        EventActionCoordinator(
            appleCalendar: AppleCalendarBridge(),
            removalService: EventKitEventRemovalService(eventStore: eventStore),
            occurrenceFinder: EventKitOccurrenceFinder(eventStore: eventStore),
            noticeCenter: noticeCenter,
            reminderSuppression: reminderSuppression,
            editor: editor,
            onNavigateOccurrence: { [agendaNavigation] target in
                await agendaNavigation.navigateToOccurrence(target)
            }
        )
    }

    /// Ask: its tools read this panel's calendar and tasks, and write
    /// through the same editor as the event popover.
    private static func makeChat(settings: AssistantSettingsStore, dataProvider: CalendarDataProviding, calendar: Calendar,
                                 taskRepository: TaskRepository, eventEditor: EventKitEventEditor) -> ChatCoordinator {
        ChatCoordinator(
            settings: settings,
            toolContext: AssistantToolContext(
                data: AppAssistantDataSource(calendarData: dataProvider, tasks: taskRepository, holidays: CachingHolidayProvider.shared),
                calendar: calendar,
                changes: AppAssistantChangeWriter(tasks: taskRepository, events: eventEditor),
                timeFormat: { .current }
            ),
            events: { [dataProvider, calendar] day in dataProvider.events(for: day, calendar: calendar) }
        )
    }

    /// Search: events from the calendar index (same visibility and
    /// declined rules as the agenda), tasks from the reminders in memory,
    /// in the lists shown.
    private static func makeSearchPalette(dataProvider: CalendarDataProviding, calendar: Calendar,
                                          taskStore: TaskStore) -> SearchPaletteModel {
        let palette = SearchPaletteModel()
        palette.eventsOn = { [dataProvider, calendar] day in dataProvider.events(for: day, calendar: calendar) }
        palette.results.searchMatches = { [dataProvider] in await dataProvider.searchEventMatches($0) }
        palette.results.searchRanked = { [dataProvider] in
            await dataProvider.searchRankedEvents($0, limit: SearchSession.rankedCandidates)
        }
        palette.results.parseQuery = {
            await SearchQueryResolver.resolve($0, referenceDate: Date(), calendar: .autoupdatingCurrent)
        }
        palette.results.loadEvents = { [dataProvider] in await dataProvider.searchEvents(ids: $0) }
        palette.results.tasks = { [taskStore] in
            taskStore.repository.tasks.filter { taskStore.listVisibility.isVisible($0.listID) }
        }
        return palette
    }
}
