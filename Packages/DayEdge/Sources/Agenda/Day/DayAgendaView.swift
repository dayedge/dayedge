import SwiftUI
import Domain
import UI

package struct DayAgendaView: View {
    @Environment(\.themePalette) var theme
    @Environment(\.timeFormat) var timeFormat
    @Environment(\.weatherProvider) private var weatherProvider

    package let date: Date
    package let isToday: Bool
    package let events: [AgendaEventModel]
    package let onPrevious: () -> Void
    package let onNext: () -> Void
    /// The header's title: back to today.
    package var onToday: () -> Void = {}
    package var keyboardNavigationRequest: VerticalNavigationRequest?
    package var positioningRequest: AgendaScrollTarget?
    package var nowPresentation: AgendaNowPresentation?
    /// `false` while `RootView` keeps this mounted but hidden
    /// behind Month mode — an up/down keypress should move whichever
    /// agenda is actually on screen, not both at once.
    package var isActive = true
    /// Fired whenever `applyPositioningIfReady` actually applies (or
    /// determines there's nothing to apply for) the current
    /// `positioningRequest` — lets `RootView` know this column's
    /// scroll position is settled, e.g. before revealing the popover
    /// window for a menu-bar-triggered "today/now" open.
    package var onPositioned: () -> Void = {}
    /// The day's reminders: untimed ones above the grid, timed ones on it.
    package var tasks: DayTasks = .none
    package var taskCoordinator: CalendarTaskCoordinator?
    package var taskCompletionRequest: TaskCompletionRequest?
    package var detailPresentationRequest: EventDetailPresentationRequest?
    package var onKeyboardSelection: (AgendaSelection?) -> Void = { _ in }
    package var onEventDetailPresentationChange: (String, Bool) -> Void = { _, _ in }

    /// Events and task cards share the content lane; overlapping ones get
    /// columns side by side (see `DayTimelineLayout`).
    var laneLayout: (events: [DayTimelineLayout.PositionedEvent], tasks: [String: DayTimelineLayout.PositionedTask]) {
        DayTimelineLayout.layout(events: events, tasks: taskMarkers.map { $0.span(minuteHeight: minuteHeight) }, day: date)
    }

    private var eventCount: Int {
        events.filter { $0.status != .cancelled }.count
    }

    private var allDayEvents: [AgendaEventModel] {
        events.filter(\.isAllDay)
    }

    @State private var weather: WeatherSummary?
    @AppStorage(GeneralSettings.showsWeatherKey) private var showsWeather = true
    @AppStorage(GeneralSettings.weatherLocationKey) private var weatherLocation = ""
    /// The location `weather` is for.
    @State private var weatherLocationShown: String?
    @AppStorage(GeneralSettings.dayStartHourKey) private var dayStartHour = GeneralSettings.defaultDayStartHour
    @State var scrollOffset: CGFloat = 0
    @State var scrollMetrics = ScrollMetrics()
    @State var scrollPosition = ScrollPosition()
    @State var appliedPositioningID: UUID?
    /// Height of the untimed-task area above the grid; every grid position
    /// is offset by it, so the grid (and its Now line) stays self-contained.
    @State var gridTopOffset: CGFloat = 0
    /// The last programmatic position, in grid coordinates — re-applied when
    /// the task area above the grid changes height, until the user scrolls.
    @State var gridAnchoredY: CGFloat?
    @State var keyboardAnchor: AgendaScrollAnchor?

    var section: AgendaDaySection {
        AgendaDaySection(date: date, events: events)
    }

    var minuteHeight: CGFloat { AppTheme.Metrics.timelineHourHeight / 60 }

    var taskMarkers: [DayTaskMarkerLayout.Marker] {
        guard taskCoordinator != nil else { return [] }
        let actions = taskCoordinator?.actions
        return DayTaskMarkerLayout.layout(
            tasks: tasks.timed, minuteHeight: minuteHeight,
            gap: AppTheme.Tasks.timelineCardGap,
            ringCenter: AppTheme.Tasks.timelineCardRingCenter
        ) { task in
            TimedTaskCardMetrics.height(hasSecondLine: TimedTaskMarkerView.hasSecondLine(task, listName: actions?.list(for: task)?.title))
        }
    }

    var activeNowPresentation: AgendaNowPresentation? {
        guard let nowPresentation,
              Calendar.autoupdatingCurrent.isDate(nowPresentation.day, inSameDayAs: date) else { return nil }
        return nowPresentation
    }

    /// A grid-relative y (minutes from midnight) in scroll-content space.
    func contentY(minutes: Int) -> CGFloat {
        gridTopOffset + CGFloat(minutes) / 60 * AppTheme.Metrics.timelineHourHeight
    }

    package var body: some View {
        VStack(spacing: 0) {
            DayHeaderView(
                date: date,
                isToday: isToday,
                eventCount: eventCount,
                taskCount: taskCoordinator == nil ? 0 : tasks.count,
                onToday: onToday,
                onPrevious: onPrevious,
                onNext: onNext
            )

            ScrollViewReader { proxy in
            ThemedScrollView(
                position: $scrollPosition,
                edgeDissolve: .all,
                topDissolve: AppTheme.ScrollEdge.tallHeader,
                isDissolveActive: isActive,
                onMetricsChange: { metrics in
                    scrollOffset = metrics.offset
                    scrollMetrics = metrics
                    applyPositioningIfReady()
                },
                // Dragging the scroll bar is the user taking over too
                // (SwiftUI reports no phase for it).
                onScrollerTracking: { tracking in
                    if tracking { gridAnchoredY = nil }
                },
                content: {
                    VStack(spacing: 0) {
                        untimedTaskArea
                        timelineContent
                    }
                }
            )
            .onScrollPhaseChange { _, phase in
                // The user took over: stop re-anchoring.
                if phase == .interacting { gridAnchoredY = nil }
            }
            .onChange(of: keyboardNavigationRequest) { _, request in
                guard isActive, let request else { return }
                moveSelection(request.direction, proxy: proxy)
            }
            .onChange(of: taskCompletionRequest) { _, request in
                guard isActive, request != nil else { return }
                completeSelectedTask(proxy: proxy)
            }
            .floatingTopBar(usesNativeEffect: false) {
                VStack(spacing: 0) {
                    if showsWeather, let weather {
                        WeatherStripView(summary: weather)
                            .padding(.top, AppTheme.Metrics.dayWeatherTopGap)
                            .padding(.bottom, AppTheme.Metrics.dayWeatherContentGap)
                    }

                    AllDayRowView(
                        date: date,
                        events: allDayEvents,
                        topPadding: showsWeather && weather != nil ? 0 : 10,
                        selectedEventID: selectedAllDayEventID,
                        detailPresentationRequest: detailPresentationRequest,
                        onDetailPresentationChange: onEventDetailPresentationChange
                    )
                }
            }
            }
        }
        .task(id: isActive ? "\(date.timeIntervalSince1970)-\(dayStartHour)" : nil) {
            guard isActive else { return }
            if let request = matchingPositioningRequest {
                applyPositioningIfReady(request)
                return
            }
            // Lands on "now" for today so you don't have to scroll down
            // past the whole morning to see what's coming up; a fixed
            // 8am for any other day, roughly where a typical day starts.
            let anchorMinutes = DayScrollAnchor.minutes(
                isToday: isToday, now: Date(), startHour: GeneralSettings.dayStartHour()
            )
            let anchorY = CGFloat(anchorMinutes) / 60 * AppTheme.Metrics.timelineHourHeight
            let target = max(anchorY - 100, 0)
            setScrollTarget(gridTopOffset + target, anchored: target)
        }
        .onChange(of: positioningRequest) { _, request in
            guard let request, Calendar.autoupdatingCurrent.isDate(request.date, inSameDayAs: date) else { return }
            appliedPositioningID = nil
            applyPositioningIfReady(request)
        }
        .onChange(of: nowPresentation) { _, _ in
            applyPositioningIfReady()
        }
        .onChange(of: events) { _, _ in
            // A recurrence jump can target a day outside the loaded agenda
            // window. Apply its event anchor once that day's events arrive.
            applyPositioningIfReady()
        }
        .onChange(of: date) { _, _ in clearSelection() }
        .task(id: isActive ? "\(date.timeIntervalSince1970)-\(showsWeather)-\(weatherLocation)" : nil) {
            guard isActive else { return }
            guard showsWeather, WeatherForecastWindow.contains(date) else {
                weather = nil
                return
            }
            // Another place's weather never stays up while this one loads.
            if weatherLocationShown != weatherLocation { weather = nil }
            // Best-effort: a plain offline dev run or a network hiccup
            // just means the weather strip stays hidden, nothing crashes.
            let fetched = try? await weatherProvider.fetchWeather(for: date, at: WeatherLocationChoice(storageValue: weatherLocation))
            guard !Task.isCancelled else { return }
            weather = fetched
            weatherLocationShown = weatherLocation
        }
    }
}
