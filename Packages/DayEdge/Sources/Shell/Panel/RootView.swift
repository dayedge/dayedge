import AppKit
import SwiftUI
import EventKit
import Domain
import Platform
import UI
import Agenda
import Tasks
import Intelligence

/// The panel: one shell for Month, Day, Tasks and Ask, the search field,
/// the toolbar and the bottom zone. Presentation only — the objects in
/// `RootModels` do the work; the columns, footers and keys are in the
/// `RootView+…` files.
struct RootView: View {
    @Environment(\.themePalette) var theme
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var presentationStyle: PanelPresentationStyle = .standalone
    var onOpenSettings: (SettingsDestination?) -> Void = { _ in }
    let indexActivity: CalendarIndexActivity?

    @State var models: RootModels
    @State var isSelectorPresented = false
    /// Ask's own: Ask stays mounted behind the other views, so sharing
    /// `isSelectorPresented` would open the chats list over theirs.
    @State var isChatSelectorPresented = false
    @FocusState var isSearchFocused: Bool
    @State var verticalNavigationRequest: VerticalNavigationRequest?
    @State var taskCompletionRequest: TaskCompletionRequest?
    /// The panel's one decision, docked at its bottom (`DecisionCard`).
    @State var decisions = DecisionCenter.shared
    @AppStorage(TaskSettings.showsInCalendarKey) var showsTasksInCalendar = true
    @AppStorage(GeneralSettings.showsWeekNumbersKey) var showsWeekNumbers = false

    init(eventStore: EKEventStore,
         dataProvider: CalendarDataProviding,
         visibilityStore: SourceVisibilityStore,
         taskRepository: TaskRepository,
         reminderSuppression: ReminderSuppressionStore,
         assistantSettings: AssistantSettingsStore,
         presentationCoordinator: PopoverPresentationCoordinator,
         calendarAccess: CalendarPermissionMonitor,
         presentationStyle: PanelPresentationStyle = .standalone,
         indexActivity: CalendarIndexActivity? = nil,
         onOpenSettings: @escaping (SettingsDestination?) -> Void = { _ in }) {
        self.indexActivity = indexActivity
        self.presentationStyle = presentationStyle
        self.onOpenSettings = onOpenSettings
        self._models = State(initialValue: RootModels(
            eventStore: eventStore,
            dataProvider: dataProvider,
            visibilityStore: visibilityStore,
            taskRepository: taskRepository,
            reminderSuppression: reminderSuppression,
            assistantSettings: assistantSettings,
            presentationCoordinator: presentationCoordinator,
            calendarAccess: calendarAccess
        ))
    }

    var router: PanelRouter { models.router }
    var agendaNavigation: AgendaNavigationCoordinator { models.agendaNavigation }
    var searchPalette: SearchPaletteModel { models.searchPalette }
    var taskStore: TaskStore { models.taskStore }

    private var pointerHeight: CGFloat { presentationStyle.pointer?.height ?? 0 }

    var isAskShown: Bool { router.isAskShown }

    /// Open search dims the panel behind its palette.
    private var isSearchScrimShown: Bool {
        router.isSearchExpanded && !isAskShown && !searchPalette.isResultsViewShown
    }

    private var chatObjects: ChatObjectContext {
        ChatObjectContext(event: models.chat.eventLookup, taskActions: taskStore.actions,
                          taskCoordinator: models.chatTasks, showDay: { router.showDay($0) })
    }

    var body: some View {
        @Bindable var router = router
        ZStack(alignment: .top) {
            // One shell for all four views: Month, Day and Tasks, and — once
            // visited — Ask, which stays mounted so its conversation persists.
            ZStack {
                calendarBody
                    .allowsHitTesting(!isAskShown)
                    .accessibilityHidden(isAskShown)

                if let chat = models.chat.current {
                    ChatView(session: chat, isPresented: isAskShown, objects: chatObjects) { chatFooter }
                    .allowsHitTesting(isAskShown)
                    .accessibilityHidden(!isAskShown)
                    // One view per conversation: switching (New chat,
                    // History) tears the old transcript down. Reused, its
                    // lazy stack kept every row it had built — measured,
                    // 242 rows of a finished chat stayed alive behind a
                    // new one.
                    .id(ObjectIdentifier(chat))
                }
            }
            .frame(minWidth: AppTheme.Metrics.popoverWidth, maxWidth: AppTheme.Metrics.popoverWidth, maxHeight: .infinity)
            .floatingSurface(radius: FloatingSurface.calendarRadius)
            .padding(.top, pointerHeight)
            // Explicit, low z-index — this is the calendar/agenda content
            // Search must always draw in front of. Set here too (not just
            // on `SearchBarView` itself) so the ordering between these two
            // particular siblings is never ambiguous/order-dependent.
            .zIndex(0)

            if let pointer = presentationStyle.pointer {
                // Part of real layout (not a floating overlay outside the
                // view's own bounds) so the hosting window sizes to
                // include it, rather than risking it being clipped.
                ThemedSurface(role: .window, fill: theme.background, shape: BubblePointerShape())
                    .frame(width: pointer.width, height: pointer.height)
                    // Dimmed with the panel under open search, so the
                    // pointer never reads lighter than the bubble. Not its
                    // last point, which overlaps the bubble's (already
                    // dimmed) top edge.
                    .overlay(alignment: .top) {
                        if isSearchScrimShown {
                            BubblePointerShape()
                                .fill(theme.chrome.searchScrim)
                                .mask(alignment: .top) { Rectangle().frame(height: max(pointer.height - 1, 0)) }
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
                    .offset(x: models.presentationCoordinator.pointerXOffset, y: 1)
                    .zIndex(0)
            }

            // Expanded search overlays the calendar/agenda/tasks content
            // below it rather than pushing it down or resizing the popup —
            // a light scrim gives it visual priority without blurring
            // anything underneath. Purely visual: no click-outside-to-
            // dismiss behavior is attached to it.
            // The whole bubble, toolbar band included — the palette draws
            // over it — so nothing around the field stays lighter.
            if isSearchScrimShown {
                theme.chrome.searchScrim
                    .allowsHitTesting(false)
                    // Rounded as the bubble itself, then moved below the
                    // pointer: clipped after the padding, its top corners
                    // were the window's, darkening slivers outside the
                    // bubble's corners.
                    .clipShape(RoundedRectangle(cornerRadius: FloatingSurface.calendarRadius, style: .continuous))
                    .padding(.top, pointerHeight)
                    .transition(.opacity)
                    .zIndex(50)
            }

            // Ask has its own header and a composer instead of the search field.
            if !isAskShown {
                SearchBarView(
                    query: $router.searchQuery,
                    searchFocus: $isSearchFocused,
                    palette: searchPalette,
                    taskCoordinator: models.searchTasks
                )
                .transition(.opacity.animation(.easeOut(duration: 0.12)))
                // Explicit here too, matching the z-index already set inside
                // `SearchBarView` itself — belt and suspenders so this surface
                // can never end up drawn under the calendar content regardless
                // of which layer the ordering ambiguity was actually coming from.
                .zIndex(100)
                // Unconditional — the same `verticalOffset` in both collapsed
                // and expanded states, so Search's own position never changes
                // when a query starts (expansion happens *around* the
                // stationary field, not as a jump to a different resting
                // spot). Applied as outer padding on this single view (not a
                // top-padding tweak inside `SearchBarView`, which would only
                // push the *content* down while the background's own top edge
                // stayed put) so the rounded corner and everything inside it
                // move together, as one surface.
                .padding(.top, pointerHeight + SearchBarView.verticalOffset)
            }

            // The panel's drag band: the pointer, the top inset and the
            // toolbar row. Under the search field, toolbar buttons and the
            // view switcher (they keep their clicks), over the content — so
            // the toolbar's empty stretches move the panel.
            // In Ask the row is the composer's, so only the strip above it.
            WindowDragBackground()
                .frame(height: pointerHeight + PanelToolbarMetrics.topInset + (isAskShown ? 0 : PanelToolbarMetrics.height))
                .zIndex(99)

            // The one toolbar row, above every view: its leading slot is the
            // view's (the search field or Ask's composer lives in the layer
            // below, so here it is just room), and the one view switcher
            // never moves.
            PanelToolbar {
                Color.clear.allowsHitTesting(false)
            } switcher: {
                viewSwitcher
                    // One place in every view, so its icons never move when
                    // the view changes: mirroring the search magnifier and
                    // Ask's send arrow — the last circle as far from the
                    // right edge as they are from the left, level with them.
                    .offset(x: PanelToolbarMetrics.switcherShift)
            }
            .padding(.top, pointerHeight + PanelToolbarMetrics.topInset)
            .zIndex(101)
        }
        .animation(.easeOut(duration: router.isSearchExpanded ? 0.16 : 0.13), value: router.isSearchExpanded)
        .frame(minWidth: AppTheme.Metrics.popoverWidth, maxWidth: AppTheme.Metrics.popoverWidth, maxHeight: .infinity)
        .modifier(PanelBottomZone(notices: models.noticeCenter, decisions: decisions))
        .environment(\.eventActionCoordinator, models.eventActions)
        .environment(\.weatherProvider, CachingWeatherService.shared)
        .environment(\.openAppSettings, onOpenSettings)
        .environment(\.reminderSuppressionStore, models.reminderSuppression)

        // The panel moves only by its empty background: content in front
        // (events, rows, buttons) always takes a press first, so dragging an
        // event can never become a window drag.
        .background {
            // Preserve normal caret navigation once the user has started a
            // search. With an empty query the arrows belong to the calendar.
            ArrowKeyMonitor(isEnabled: router.searchQuery.isEmpty && !isAskShown, onArrowKey: handleArrowKey)
                .frame(width: 0, height: 0)
            ViewModeShortcutMonitor(onSelectMode: { router.selectViewMode($0) })
                .frame(width: 0, height: 0)
            ActionShortcutMonitor(
                // The sort menu owns ↑ ↓ Return while it is open.
                isNavigationEnabled: router.searchQuery.isEmpty && !isAskShown && !taskStore.isSortMenuPresented && !isSelectorPresented,
                onAction: handleShortcutAction
            )
            .frame(width: 0, height: 0)
        }
        .modifier(lifecycle)
    }

    /// The triggers that keep the panel current; `PanelRefreshCoordinator`
    /// and `PanelRouter` do the work.
    private var lifecycle: RootLifecycle {
        RootLifecycle(models: models, reduceMotion: reduceMotion, calendarTaskIndex: calendarTaskIndex,
                      focusSearch: { _ = handleShortcutAction(.focusSearch) })
    }
}
