import SwiftUI
import Domain
import UI

/// Native lazy agenda with system-pinned day headers. Programmatic
/// navigation is ID-based, so no per-row geometry preferences or per-frame
/// document-position calculations are needed.
package struct AgendaListView: View {
    @Environment(\.themePalette) var theme
    @Environment(\.timeFormat) var timeFormat

    package let store: AgendaSectionStore
    package var scrollTarget: AgendaScrollTarget?
    package var nowPresentation: AgendaNowPresentation?
    package var keyboardNavigationRequest: VerticalNavigationRequest?
    package var detailPresentationRequest: EventDetailPresentationRequest?
    package var detailActionRequest: EventDetailActionRequest?
    /// Scheduled reminders, bucketed by day. Compared by signature, so a
    /// task change re-renders the list once, like an event change.
    package var taskIndex: ScheduledTaskIndex = .empty
    package var taskCoordinator: CalendarTaskCoordinator?
    package var taskCompletionRequest: TaskCompletionRequest?
    package var onCurrentSectionChange: (Date) -> Void = { _ in }
    package var onKeyboardSelection: (AgendaSelection?) -> Void = { _ in }
    package var onEventDetailPresentationChange: (String, Bool) -> Void = { _, _ in }
    package var onEventDetailActionFocusChange: (String, EventDetailFocusableAction?) -> Void = { _, _ in }
    package var isActive = true
    package var onScrollPrepared: (AgendaScrollTarget) -> Void = { _ in }

    @State private var weather = AgendaWeatherStore()
    @Environment(\.weatherProvider) private var weatherProvider
    @AppStorage(GeneralSettings.weatherLocationKey) private var weatherLocation = ""
    @AppStorage(GeneralSettings.showsWeatherKey) private var showsWeather = true
    @State var scroll: AgendaScrollCoordinator
    /// While the list moves, its rows don't take the pointer: no hover
    /// states or tracking areas recomputed as rows slide under it (measured
    /// per frame). A click during momentum still stops the scroll.
    @State private var isScrolling = false

    package init(store: AgendaSectionStore,
                 scrollTarget: AgendaScrollTarget? = nil,
                 nowPresentation: AgendaNowPresentation? = nil,
                 keyboardNavigationRequest: VerticalNavigationRequest? = nil,
                 detailPresentationRequest: EventDetailPresentationRequest? = nil,
                 detailActionRequest: EventDetailActionRequest? = nil,
                 taskIndex: ScheduledTaskIndex = .empty,
                 taskCoordinator: CalendarTaskCoordinator? = nil,
                 taskCompletionRequest: TaskCompletionRequest? = nil,
                 onCurrentSectionChange: @escaping (Date) -> Void = { _ in },
                 onKeyboardSelection: @escaping (AgendaSelection?) -> Void = { _ in },
                 onEventDetailPresentationChange: @escaping (String, Bool) -> Void = { _, _ in },
                 onEventDetailActionFocusChange: @escaping (String, EventDetailFocusableAction?) -> Void = { _, _ in },
                 isActive: Bool = true,
                 onScrollPrepared: @escaping (AgendaScrollTarget) -> Void = { _ in }) {
        self.store = store
        self.scrollTarget = scrollTarget
        self.nowPresentation = nowPresentation
        self.keyboardNavigationRequest = keyboardNavigationRequest
        self.detailPresentationRequest = detailPresentationRequest
        self.detailActionRequest = detailActionRequest
        self.taskIndex = taskIndex
        self.taskCoordinator = taskCoordinator
        self.taskCompletionRequest = taskCompletionRequest
        self.onCurrentSectionChange = onCurrentSectionChange
        self.onKeyboardSelection = onKeyboardSelection
        self.onEventDetailPresentationChange = onEventDetailPresentationChange
        self.onEventDetailActionFocusChange = onEventDetailActionFocusChange
        self.isActive = isActive
        self.onScrollPrepared = onScrollPrepared
        _scroll = State(initialValue: AgendaScrollCoordinator(store: store, scrollTarget: scrollTarget))
    }

    private var sections: [AgendaDaySection] { store.sections }

    private func eventCount(for section: AgendaDaySection) -> Int {
        section.events.filter { $0.status != .cancelled }.count
    }

    private var agendaContent: some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: theme.agendaPinnedViews) {
            if store.isLoadingAtTop {
                loadingEdgeRow
            }

            ForEach(sections) { section in
                Section {
                    sectionContent(section)
                } header: {
                    AgendaDayHeaderView(
                        date: section.date,
                        isToday: section.isToday,
                        eventCount: eventCount(for: section),
                        taskCount: taskCoordinator == nil ? 0 : taskIndex.tasks(on: section.date).count,
                        weather: showsWeather ? weather.weatherBySection[section.id] : nil,
                        tooltipPlacement: .below
                    )
                }
                .id(AgendaScrollAnchor.day(section.id))
            }

            if store.isLoadingAtBottom {
                loadingEdgeRow
            }
        }
        .scrollTargetLayout()
        .padding(.bottom, 12)
    }

    /// Set while the list is on screen, so a row's completion can move the
    /// keyboard selection through the scroll proxy. A reference: rows that
    /// skip rebuilding (`EquatableRow`) still reach the current handler.
    @State var completion = CompletionHandlerBox()

    package var body: some View {
        ScrollViewReader { proxy in
            ThemedScrollView(
                edgeDissolve: .bottom,
                isDissolveActive: isActive,
                onScrollerTracking: { tracking in
                    scroll.scrollerTrackingChanged(tracking, proxy: proxy, onCurrentSectionChange: onCurrentSectionChange)
                },
                content: {
                    agendaContent
                        .allowsHitTesting(!isScrolling)
                }
            )
            .onScrollTargetVisibilityChange(idType: AgendaScrollAnchor.self, threshold: 0.01) { anchors in
                scroll.visibilityChanged(anchors, isActive: isActive, proxy: proxy, onCurrentSectionChange: onCurrentSectionChange)
            }
            .onScrollPhaseChange { _, phase in
                if isScrolling != phase.isScrolling { isScrolling = phase.isScrolling }
                scroll.scrollPhaseChanged(isTracking: phase == .tracking || phase == .interacting || phase == .decelerating)
            }
            .onAppear {
                if let scrollTarget {
                    scroll.handleScrollRequest(
                        scrollTarget, nowPresentation: nowPresentation, isActive: isActive, proxy: proxy,
                        onKeyboardSelection: onKeyboardSelection, onScrollPrepared: onScrollPrepared
                    )
                } else {
                    scroll.clearProgrammaticFlagIfNoTarget()
                }
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                scroll.handleScrollRequest(
                    target, nowPresentation: nowPresentation, isActive: isActive, proxy: proxy,
                    onKeyboardSelection: onKeyboardSelection, onScrollPrepared: onScrollPrepared
                )
            }
            .onChange(of: taskIndex, initial: true) { _, index in
                scroll.taskIndex = index
            }
            .onChange(of: nowPresentation, initial: true) { _, presentation in
                scroll.nowPresentation = presentation
            }
            .onAppear {
                completion.handler = { taskID, sectionID in
                    guard let taskCoordinator else { return }
                    withAnimation(.smooth(duration: 0.25)) {
                        scroll.taskCompleted(taskID, in: sectionID, proxy: proxy,
                                             complete: taskCoordinator.complete, onKeyboardSelection: onKeyboardSelection)
                    }
                }
            }
            .onChange(of: taskCompletionRequest) { _, request in
                guard isActive, request != nil, let taskCoordinator else { return }
                withAnimation(.smooth(duration: 0.25)) {
                    _ = scroll.completeSelectedTask(proxy: proxy, complete: taskCoordinator.complete,
                                                    onKeyboardSelection: onKeyboardSelection)
                }
            }
            .onChange(of: keyboardNavigationRequest) { _, request in
                guard isActive, let request else { return }
                scroll.moveOneEvent(request.direction, proxy: proxy, onKeyboardSelection: onKeyboardSelection)
            }
            .onDisappear {
                scroll.cancelNavigation()
            }
            // A cheap key for the loaded days (not every day's id, rebuilt
            // on each redraw).
            .task(id: showsWeather ? WeatherKey(sections, location: weatherLocation) : nil) {
                guard showsWeather else { return }
                weather.provider = weatherProvider
                await weather.refresh(for: sections, at: WeatherLocationChoice(storageValue: weatherLocation))
            }
        }
    }

    func nowPresentation(for section: AgendaDaySection) -> AgendaNowPresentation? {
        let calendar = Calendar.autoupdatingCurrent
        guard let nowPresentation,
              calendar.isDate(nowPresentation.day, inSameDayAs: section.date) else { return nil }
        return nowPresentation
    }
}

extension AgendaListView: Equatable {
    package static func == (lhs: AgendaListView, rhs: AgendaListView) -> Bool {
        lhs.store === rhs.store &&
        lhs.scrollTarget == rhs.scrollTarget &&
        lhs.nowPresentation == rhs.nowPresentation &&
        lhs.keyboardNavigationRequest == rhs.keyboardNavigationRequest &&
        lhs.detailPresentationRequest == rhs.detailPresentationRequest &&
        lhs.detailActionRequest == rhs.detailActionRequest &&
        lhs.taskIndex == rhs.taskIndex &&
        lhs.taskCoordinator === rhs.taskCoordinator &&
        lhs.taskCompletionRequest == rhs.taskCompletionRequest &&
        lhs.isActive == rhs.isActive
    }
}

/// What an agenda row shows: rows are redrawn only when this changes, not
/// whenever the list redraws (a loaded page, weather, the scroll flag).
package struct AgendaRowKey: Equatable {
    package var event: AgendaEventModel?
    package var task: TaskItem?
    package var date: Date
    package var isKeyboardSelected = false
    package var isOngoing = false
    package var isOverdue = false
    package var isToday = false
    package var isActive = true
    package var isProjected = false
    package var detailPresentationRequest: EventDetailPresentationRequest?
    package var detailActionRequest: EventDetailActionRequest?
    /// Times are written in it: a change redraws the rows.
    package var timeFormat: TimeFormat

    package init(event: AgendaEventModel? = nil, task: TaskItem? = nil, date: Date, isKeyboardSelected: Bool = false,
                 isOngoing: Bool = false, isOverdue: Bool = false, isToday: Bool = false, isActive: Bool = true,
                 isProjected: Bool = false, detailPresentationRequest: EventDetailPresentationRequest? = nil,
                 detailActionRequest: EventDetailActionRequest? = nil, timeFormat: TimeFormat = .twentyFourHour) {
        self.event = event
        self.task = task
        self.date = date
        self.isKeyboardSelected = isKeyboardSelected
        self.isOngoing = isOngoing
        self.isOverdue = isOverdue
        self.isToday = isToday
        self.isActive = isActive
        self.isProjected = isProjected
        self.detailPresentationRequest = detailPresentationRequest
        self.detailActionRequest = detailActionRequest
        self.timeFormat = timeFormat
    }
}

/// A row compared by its key; its content (with closures SwiftUI can't
/// compare) is rebuilt only when the key changes.
package struct EquatableRow<Key: Equatable, Content: View>: View, Equatable {
    package let key: Key
    @ViewBuilder package let content: () -> Content

    package static func == (a: EquatableRow, b: EquatableRow) -> Bool { a.key == b.key }

    package var body: some View { content() }
}

/// The loaded days, cheaply: enough to know when they changed.
private struct WeatherKey: Equatable {
    let count: Int
    let first: Date?
    let last: Date?
    /// The weather location: a new one refetches (and cancels the old fetch).
    let location: String

    init(_ sections: [AgendaDaySection], location: String) {
        count = sections.count
        first = sections.first?.id
        last = sections.last?.id
        self.location = location
    }
}

/// Holds the list's task-completion handler for rows to call.
final class CompletionHandlerBox {
    var handler: ((String, Date) -> Void)?
}
