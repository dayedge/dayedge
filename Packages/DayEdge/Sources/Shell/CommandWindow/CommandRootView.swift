import SwiftUI
import Domain
import Platform
import UI
import Agenda
import Intelligence

/// The Command Window (⌃⌥D): the panel's views, laid out for a wide window
/// — the command bar on top, the view in the middle, one footer row. The
/// same `RootModels` as the popover's `RootView`, so date, view, search,
/// filters and chat are one; only focus and presentation are this window's.
/// The popover's `RootLifecycle` keeps the shared models current for both.
struct CommandRootView: View {
    @Environment(\.themePalette) var theme

    let models: RootModels
    let presentation: PanelHostPresentation
    let indexActivity: CalendarIndexActivity?
    let onOpenSettings: (SettingsDestination?) -> Void
    /// Esc with nothing left to close.
    let onClose: () -> Void

    @State var isSelectorPresented = false
    @State var isActionsPresented = false
    @FocusState var isSearchFocused: Bool
    @State var verticalNavigationRequest: VerticalNavigationRequest?
    @State var taskCompletionRequest: TaskCompletionRequest?
    /// The panel's one decision, docked at its bottom (`DecisionCard`).
    @State var decisions = DecisionCenter.shared
    @AppStorage(TaskSettings.showsInCalendarKey) var showsTasksInCalendar = true
    @AppStorage(GeneralSettings.showsWeekNumbersKey) var showsWeekNumbers = false

    init(models: RootModels, presentation: PanelHostPresentation, indexActivity: CalendarIndexActivity?,
         onOpenSettings: @escaping (SettingsDestination?) -> Void, onClose: @escaping () -> Void) {
        self.models = models
        self.presentation = presentation
        self.indexActivity = indexActivity
        self.onOpenSettings = onOpenSettings
        self.onClose = onClose
    }

    var router: PanelRouter { models.router }
    var searchPalette: SearchPaletteModel { models.searchPalette }

    /// The command bar's row: the field and the space around it.
    static let commandBarHeight: CGFloat = PanelToolbarMetrics.height + 2 * commandBarInset
    static let commandBarInset: CGFloat = 12

    var body: some View {
        @Bindable var router = router
        VStack(spacing: 0) {
            // The command bar draws over this room, so its palette can open
            // over the view below without moving it. Ask's composer is the
            // top row there, as in the popover: no command bar above it.
            // Around the field, the room moves the window (no title bar).
            if !router.isAskShown {
                WindowDragBackground().frame(height: Self.commandBarHeight)
                WorkspaceRule(.section)
            }
            // Only while open: hidden, the views would redraw with every
            // change the popover makes to the shared models.
            Group {
                if presentation.isPresented { workspace }
            }
            .takesOfferedSize()
            WorkspaceRule(.section)
            CommandFooterBar(models: models, isSelectorPresented: $isSelectorPresented,
                             isActionsPresented: $isActionsPresented, keyHandler: keyHandler,
                             indexActivity: indexActivity, onOpenSettings: onOpenSettings)
        }
        .takesOfferedSize()
        // In Ask, the strip above the composer moves the window.
        .background(alignment: .top) {
            if router.isAskShown { WindowDragBackground().frame(height: Self.commandBarInset) }
        }
        .overlay {
            if router.isSearchScrimShown {
                theme.chrome.searchScrim
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        // The command bar alone: views (⌘1–4) and Settings are in Actions.
        .overlay(alignment: .top) {
            if !router.isAskShown {
                SearchBarView(query: $router.searchQuery, searchFocus: $isSearchFocused, palette: searchPalette,
                              taskCoordinator: models.searchTasks)
                    .padding(.top, Self.commandBarInset)
                    .padding(.horizontal, Self.commandBarInset - SearchBarView.surfaceHorizontalInset)
            }
        }
        .animation(.easeOut(duration: router.isSearchExpanded ? 0.16 : 0.13), value: router.isSearchExpanded)
        .floatingSurface(radius: FloatingSurface.calendarRadius)
        .modifier(PanelBottomZone(notices: models.noticeCenter, decisions: decisions))
        .modifier(PanelEnvironment(models: models, onOpenSettings: onOpenSettings))
        .environment(\.panelLayout, .wide)
        .modifier(PanelKeyMonitors(handler: keyHandler))
        // Every open: ready for typing.
        .onChange(of: presentation.revealID) { _, _ in
            _ = keyHandler.handleShortcutAction(.focusSearch)
        }
    }

    private var keyHandler: PanelKeyHandler {
        PanelKeyHandler(models: models,
                        verticalNavigationRequest: $verticalNavigationRequest,
                        taskCompletionRequest: $taskCompletionRequest,
                        isSearchFocused: $isSearchFocused,
                        isSelectorPresented: $isSelectorPresented,
                        isActionsPresented: $isActionsPresented,
                        openSettings: { onOpenSettings(nil) },
                        onEscapeAtRoot: onClose)
    }

    var calendarTaskIndex: ScheduledTaskIndex {
        models.calendarTaskIndex(showsTasksInCalendar: showsTasksInCalendar)
    }

    /// A view is on screen: its mode, and no Search view over it. Month and
    /// Day only with Calendar access (the access card instead).
    func isColumnShown(_ mode: ViewMode) -> Bool {
        guard !searchPalette.isResultsViewShown, models.agendaNavigation.displayedViewMode == mode else { return false }
        return mode == .tasks || mode == .ask || models.calendarAccess.isGranted
    }

    /// Month asked for, still on its way (`revealMonthIfPrepared`).
    private var isMonthPreparing: Bool {
        let navigation = models.agendaNavigation
        return navigation.selectedViewMode == .month && navigation.displayedViewMode != .month
            && models.calendarAccess.isGranted && !searchPalette.isResultsViewShown
    }

    /// The view on screen; the Search view over it while it's open. Only
    /// that one exists: the wide views are costly to lay out, and hidden
    /// ones stacked under it were re-measured on every frame of a scroll
    /// (measured). Their state is the shared models', so switching back
    /// lands where they were.
    private var workspace: some View {
        ZStack {
            // Month also while it's asked for but not yet shown: its agenda
            // must reach the selected day before it appears (as the
            // popover's hidden Month does), so it's built — invisibly — to
            // get there, then shown as the same view.
            if isColumnShown(.month) || isMonthPreparing {
                monthWorkspace
                    .opacity(isColumnShown(.month) ? 1 : 0)
                    .allowsHitTesting(isColumnShown(.month))
                    .accessibilityHidden(!isColumnShown(.month))
                    .transition(.opacity)
            }
            if isColumnShown(.day) { dayWorkspace.transition(.opacity) }
            if isColumnShown(.tasks) { tasksWorkspace.transition(.opacity) }
            if isColumnShown(.ask) { askWorkspace.transition(.opacity) }
            if models.isAccessCardShown {
                PermissionStateView(subject: .calendar, status: models.calendarAccess.status) {
                    models.refresh.requestCalendarAccess()
                }
                .zIndex(1)
            }
            if searchPalette.isResultsViewShown {
                SearchResultsView(session: searchPalette.results, palette: searchPalette,
                                  taskCoordinator: models.searchTasks)
                    .zIndex(2)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: models.agendaNavigation.displayedViewMode)
    }
}

extension View {
    /// Exactly the size offered (`width` when given), whatever the content
    /// inside would like: the stacks around it then never ask it. Asked, a
    /// wide view's whole subtree — every text — was measured again on each
    /// frame of a scroll (measured). The popover's fixed width does the same.
    func takesOfferedSize(width: CGFloat? = nil) -> some View {
        frame(minWidth: width ?? 0, maxWidth: width ?? .infinity, minHeight: 0, maxHeight: .infinity)
    }
}
