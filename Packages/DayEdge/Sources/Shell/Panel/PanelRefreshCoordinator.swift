import EventKit
import Foundation
import SwiftUI
import Domain
import Platform
import UI
import Agenda
import Tasks
import Intelligence

/// Keeps what the panel shows current: Calendar access and the first
/// load, reloads when calendars, settings or events change, Reminders on
/// reopening, and "now" once a minute while the panel is on screen.
/// `RootView` keeps the triggers (so they live exactly as long as it
/// does); the work is here.
@MainActor
final class PanelRefreshCoordinator {
    private let eventStore: EKEventStore
    private let viewModel: CalendarViewModel
    private let agendaStore: AgendaSectionStore
    private let visibilityStore: SourceVisibilityStore
    private let agendaNavigation: AgendaNavigationCoordinator
    private let searchPalette: SearchPaletteModel
    private let taskStore: TaskStore
    private let noticeCenter: NoticeCenter
    private let reminderSuppression: ReminderSuppressionStore
    private let presentationCoordinator: PopoverPresentationCoordinator
    private let calendarAccess: CalendarPermissionMonitor
    private let eventDetail: EventDetailCoordinator
    private var lastShowsDeclined = GeneralSettings.showsDeclined()

    init(eventStore: EKEventStore, viewModel: CalendarViewModel, agendaStore: AgendaSectionStore,
         visibilityStore: SourceVisibilityStore, agendaNavigation: AgendaNavigationCoordinator,
         searchPalette: SearchPaletteModel, taskStore: TaskStore, noticeCenter: NoticeCenter,
         reminderSuppression: ReminderSuppressionStore, presentationCoordinator: PopoverPresentationCoordinator,
         calendarAccess: CalendarPermissionMonitor, eventDetail: EventDetailCoordinator) {
        self.eventStore = eventStore
        self.viewModel = viewModel
        self.agendaStore = agendaStore
        self.visibilityStore = visibilityStore
        self.agendaNavigation = agendaNavigation
        self.searchPalette = searchPalette
        self.taskStore = taskStore
        self.noticeCenter = noticeCenter
        self.reminderSuppression = reminderSuppression
        self.presentationCoordinator = presentationCoordinator
        self.calendarAccess = calendarAccess
        self.eventDetail = eventDetail
    }

    func requestAccessAndLoad() async {
        guard AppConfiguration.calendarBackend == .eventKit else { return }
        guard await EventKitAccess.requestAccessIfNeeded(eventStore: eventStore) else { return }

        let calendars = EventKitAccess.calendarSources(eventStore: eventStore)
        visibilityStore.update(calendars)
        viewModel.reload()
        await agendaStore.loadInitialWindow(around: viewModel.selectedDate)
    }

    /// Calendar selection changed (popover menu or Settings).
    func sourceVisibilityDidChange() {
        reloadCalendar()
    }

    func defaultsDidChange() {
        viewModel.setFirstWeekday(GeneralSettings.weekStart().firstWeekday())
        let showsDeclined = GeneralSettings.showsDeclined()
        if showsDeclined != lastShowsDeclined {
            lastShowsDeclined = showsDeclined
            reloadCalendar()
        }
    }

    /// Posted once the calendar index has committed a change (an event
    /// added/edited/removed here or on another synced device) — but
    /// that alone doesn't refresh what's already on screen —
    /// `AgendaSectionStore.sections` just keeps
    /// showing whatever it last loaded until something explicitly
    /// reloads it. This is that something: the same `reload(around:)`
    /// path the calendar-visibility toggles already use.
    func calendarEventsDidChange(animation: Animation?) {
        searchPalette.results.refresh()
        viewModel.reload()
        // An outside change lands in place: new, removed or edited
        // events animate where they are; nothing else moves.
        Task {
            await agendaStore.reload(around: viewModel.selectedDate, animation: animation)
            // "Now" follows the events: a moved or deleted meeting can
            // change what's next ("Free until …") and where the now line
            // sits — re-evaluated once the reload landed (it only changes
            // what actually differs).
            agendaNavigation.refreshNowPresentation(at: .now)
        }
    }

    func tasksDidChange() {
        searchPalette.results.refresh()
    }

    func agendaSectionsDidChange(_ sections: [AgendaDaySection]) {
        reminderSuppression.reconcile(sections.flatMap(\.events))
    }

    func panelVisibilityDidChange(_ visible: Bool) {
        if !visible { noticeCenter.dismiss() }
        // Opening is a good moment to notice a changed permission.
        if visible { calendarAccess.check() }
        // Reminders may have changed (or been allowed) while away.
        if visible { Task { await taskStore.repository.reload() } }
    }

    /// Moves "now" on at every full minute while the panel is on screen.
    func runMinuteClock() async {
        guard presentationCoordinator.isVisible else { return }
        while !Task.isCancelled {
            let now = Date.now
            let seconds = Calendar.autoupdatingCurrent.component(.second, from: now)
            let wait = UInt64(max(60 - seconds, 1)) * 1_000_000_000
            do {
                try await Task.sleep(nanoseconds: wait)
            } catch {
                return
            }
            guard presentationCoordinator.isVisible else { return }
            agendaNavigation.refreshNowPresentation(at: .now)
        }
    }

    /// Calendar access went away: nothing about an event stays on screen —
    /// its details, a decision about it, a search result's details. The
    /// views themselves empty on the reload that follows.
    func calendarAccessDidChange(_ status: SourceAccessStatus) {
        guard status != .granted else { return }
        _ = eventDetail.dismissPresentedDetails()
        eventDetail.clearKeyboardSelection()
        DecisionCenter.shared.cancel()
        _ = searchPalette.dismissResultDetails()
    }

    /// The card's button: ask (first time) or open System Settings.
    func requestCalendarAccess() {
        switch calendarAccess.status {
        case .granted: return
        case .denied: EventKitAccess.openPrivacySettings(for: .event)
        case .notDetermined:
            Task {
                _ = await EventKitAccess.requestAccessIfNeeded(eventStore: eventStore)
                calendarAccess.check()
            }
        }
    }

    private func reloadCalendar() {
        viewModel.reload()
        Task { await agendaStore.reload(around: viewModel.selectedDate) }
    }
}
