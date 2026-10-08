import SwiftUI
import Domain

/// The panel's triggers: what makes it load, reload, follow the clock and
/// answer the status menu. Only the "when" is here — the work is in
/// `PanelRefreshCoordinator`, `PanelRouter` and `ChatCoordinator`.
struct RootLifecycle: ViewModifier {
    let models: RootModels
    let reduceMotion: Bool
    let calendarTaskIndex: ScheduledTaskIndex
    let focusSearch: () -> Void

    func body(content: Content) -> some View {
        let refresh = models.refresh
        let router = models.router
        let presentation = models.presentationCoordinator
        content
            .task { await refresh.requestAccessAndLoad() }
            .onReceive(NotificationCenter.default.publisher(for: .sourceVisibilityDidChange, object: models.visibilityStore)) { _ in
                refresh.sourceVisibilityDidChange()
            }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                refresh.defaultsDidChange()
            }
            .onReceive(NotificationCenter.default.publisher(for: .calendarEventsDidChange)) { _ in
                refresh.calendarEventsDidChange(animation: reduceMotion ? nil : .smooth(duration: 0.25))
            }
            .onChange(of: models.taskStore.repository.revision) { _, _ in refresh.tasksDidChange() }
            .onChange(of: reduceMotion, initial: true) { _, reduce in router.reduceMotion = reduce }
            .onChange(of: models.assistantSettings.settings) { _, _ in models.chat.settingsDidChange() }
            .onChange(of: models.agendaNavigation.displayedViewMode) { _, _ in
                // Selection belongs to the view it was made in.
                models.eventDetail.clearKeyboardSelection()
                models.calendarTasks.select(nil)
                models.calendarTasks.dismissDetail()
            }
            .onChange(of: calendarTaskIndex) { _, _ in
                // A task can end (or stop ending) the "Free until" gap.
                models.agendaNavigation.refreshNowPresentation(at: .now)
            }
            .onChange(of: models.agendaStore.sections) { _, sections in refresh.agendaSectionsDidChange(sections) }
            .onChange(of: presentation.isVisible) { _, visible in refresh.panelVisibilityDidChange(visible) }
            .onChange(of: models.calendarAccess.status) { _, status in refresh.calendarAccessDidChange(status) }
            .task(id: presentation.openRequest?.id) {
                guard let request = presentation.openRequest else { return }
                router.handleOpenRequest(request)
            }
            .task(id: presentation.command?.id) {
                guard let request = presentation.command else { return }
                await router.perform(request.command, focusSearch: focusSearch)
            }
            .task(id: presentation.isVisible) { await refresh.runMinuteClock() }
    }
}
