import SwiftUI
import Domain
import UI

/// The detailed Search view: the Month agenda's list — the same day
/// headers, rows, details bubbles and keys — for everything the query
/// matched, without the month grid. Opens where browsing starts (today, or
/// the nearest day with results). Paged like the agenda: only a window of
/// days is rendered (`SearchDayPaging`), growing as the reader nears an
/// edge; within it, only the days on screen (plus a margin) have their
/// events loaded, the rest are placeholders until scrolled to.
package struct SearchResultsView: View {
    @Environment(\.themePalette) private var theme

    package let session: SearchSession
    package let palette: SearchPaletteModel
    package let taskCoordinator: CalendarTaskCoordinator

    /// The result days rendered (positions in `session.index.days`); the
    /// session loads exactly their events.
    @State private var dayWindow: Range<Int> = 0..<0 {
        didSet { if dayWindow != oldValue { session.show(days: dayWindow) } }
    }
    /// Re-anchoring after the window changed above the screen — kept out
    /// of view state, and visibility reports meanwhile are ignored.
    @State private var paging = PagingState()
    /// While the list moves, rows don't take the pointer (no hover or
    /// tracking-area upkeep as they slide under it).
    @State private var isScrolling = false
    private let calendar = Calendar.autoupdatingCurrent

    package var body: some View {
        VStack(spacing: 0) {
            statusBar
            if session.index.isEmpty {
                emptyState
            } else {
                results
            }
        }
    }

    // MARK: - Status

    /// "128 results".
    private var statusBar: some View {
        HStack(spacing: 12) {
            Text(statusText)
                .font(.system(size: 11.5))
                .foregroundStyle(theme.secondaryText)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, AppTheme.horizontalPadding)
        .frame(height: 28)
    }

    private var statusText: String {
        if !session.hasQuery { return L10n.tr("search.minimum.characters", "Type at least \(SearchSession.minimumCharacters) letters") }
        return session.summary
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack {
            if session.hasQuery, !session.isPending {
                Text(L10n.tr("searchresultsview.no.results.for", "No results for “\(String(describing: session.query))”"))
                    .font(AppTheme.TextStyle.eventSubtitle)
                    .foregroundStyle(theme.secondaryText)
                    .padding(.top, 24)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Results

    private var results: some View {
        // One snapshot per render: a section and its rows always read the
        // same results, even while the query swaps them underneath.
        let index = session.index
        return ScrollViewReader { proxy in
            ThemedScrollView(edgeDissolve: .bottom) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: theme.agendaPinnedViews) {
                    // Only the window's days: a query matching years of
                    // days must not build years of sections.
                    ForEach(dayWindow.clamped(to: index.days.indices), id: \.self) { dayIndex in
                        let day = index.days[dayIndex]
                        Section {
                            dayContent(day, at: dayIndex, in: index)
                        } header: {
                            dayHeader(day)
                        }
                        .id(SearchAnchor.day(dayIndex))
                    }
                }
                .scrollTargetLayout()
                .padding(.bottom, 12)
                .allowsHitTesting(!isScrolling)
            }
            .onScrollTargetVisibilityChange(idType: SearchAnchor.self, threshold: 0.01) { anchors in
                visibilityChanged(anchors, proxy: proxy)
            }
            .onScrollPhaseChange { _, phase in
                if isScrolling != phase.isScrolling { isScrolling = phase.isScrolling }
            }
            .onAppear { open(proxy) }
            .onChange(of: session.revision) { _, _ in open(proxy) }
            .onChange(of: session.selectedEntry) { _, entry in
                guard let entry, let day = session.index.dayIndex(containing: entry) else { return }
                let window = SearchDayPaging.showing(day, in: dayWindow, dayCount: session.index.days.count)
                guard window != dayWindow else {
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(SearchAnchor.entry(day: day, position: entry)) }
                    return
                }
                // Far away: open the window there, then go to it.
                dayWindow = window
                scroll(to: .entry(day: day, position: entry), anchor: .center, proxy: proxy)
            }
        }
    }

    /// A new query (or the view appearing): the window around where
    /// browsing starts, scrolled to it.
    private func open(_ proxy: ScrollViewProxy) {
        let index = session.index
        dayWindow = SearchDayPaging.opening(at: index.anchorDayIndex, dayCount: index.days.count)
        guard let anchor = index.anchorDayIndex else { return }
        scroll(to: .day(anchor), anchor: .top, proxy: proxy)
    }

    /// Days on screen: the window pages near an edge — re-anchored on the
    /// top day when days above changed.
    private func visibilityChanged(_ anchors: [SearchAnchor], proxy: ScrollViewProxy) {
        guard !paging.isRestoring, let first = anchors.map(\.day).min(), let last = anchors.map(\.day).max() else { return }
        guard let next = SearchDayPaging.paged(dayWindow, visible: first...last, dayCount: session.index.days.count)
        else { return }
        let aboveChanged = next.lowerBound != dayWindow.lowerBound
        dayWindow = next
        if aboveChanged { scroll(to: .day(first), anchor: .top, proxy: proxy) }
    }

    /// Once the lazy stack has the window's days, without animation;
    /// visibility reports meanwhile are transient and ignored.
    private func scroll(to target: SearchAnchor, anchor: UnitPoint, proxy: ScrollViewProxy) {
        paging.isRestoring = true
        Task { @MainActor in
            await Task.yield()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { proxy.scrollTo(target, anchor: anchor) }
            paging.isRestoring = false
        }
    }

    private func dayHeader(_ day: SearchIndex.Day) -> some View {
        Group {
            if let date = day.day {
                AgendaDayHeaderView(
                    date: date,
                    isToday: calendar.isDateInToday(date),
                    eventCount: day.eventCount,
                    taskCount: day.taskCount
                )
            } else {
                AgendaDayHeaderView(date: nil, isToday: false, taskCount: day.taskCount)
            }
        }
    }

    @ViewBuilder
    private func dayContent(_ day: SearchIndex.Day, at dayIndex: Int, in index: SearchIndex) -> some View {
        let date = day.day ?? calendar.startOfDay(for: Date())
        // Positions outside these results (a stale section mid-update) are
        // simply not drawn.
        ForEach(Array(day.range.clamped(to: index.entries.indices)), id: \.self) { position in
            entryRow(index.entries[position], at: position, on: date)
                .id(SearchAnchor.entry(day: dayIndex, position: position))
        }
    }

    private func entryRow(_ entry: SearchIndex.Entry, at position: Int, on date: Date) -> some View {
        SearchEntryRow(entry: entry, event: session.event(for: entry), position: position, date: date,
                       isSelected: session.selectedEntry == position, detailRequest: palette.eventDetailRequest,
                       session: session, palette: palette, taskCoordinator: taskCoordinator)
            .equatable()
    }

    package init(session: SearchSession, palette: SearchPaletteModel, taskCoordinator: CalendarTaskCoordinator) {
        self.session = session
        self.palette = palette
        self.taskCoordinator = taskCoordinator
    }
}

/// One result row, compared by what it shows: a loaded batch or a moved
/// selection redraws only the rows it touches.
private struct SearchEntryRow: View, Equatable {
    let entry: SearchIndex.Entry
    let event: AgendaEventModel?
    let position: Int
    let date: Date
    let isSelected: Bool
    let detailRequest: EventDetailPresentationRequest?
    let session: SearchSession
    let palette: SearchPaletteModel
    let taskCoordinator: CalendarTaskCoordinator

    static func == (a: SearchEntryRow, b: SearchEntryRow) -> Bool {
        a.entry == b.entry && a.event == b.event && a.position == b.position && a.date == b.date
            && a.isSelected == b.isSelected && a.detailRequest == b.detailRequest
    }

    var body: some View {
        rowView
            // Its menus offer Tab's "Show in Calendar / Tasks" too.
            .environment(\.searchResultReveal, reveal)
    }

    /// What Tab does for this row.
    private var reveal: (() -> Void)? {
        session.rowItem(at: position).map { item in { [palette] in palette.onShowResult(item) } }
    }

    @ViewBuilder
    private var rowView: some View {
        switch entry {
        case .event:
            if let event {
                if event.isAllDay {
                    AllDayEventTagView(
                        event: event,
                        date: date,
                        detailPresentationRequest: detailRequest,
                        onDetailPresentationChange: { palette.eventDetailPresentationChanged(eventID: event.id, isShowing: $0) },
                        isKeyboardSelected: isSelected
                    )
                    .padding(.horizontal, AppTheme.horizontalPadding)
                    .padding(.vertical, 3)
                    .simultaneousGesture(TapGesture().onEnded { session.select(entry: position) })
                } else {
                    AgendaEventRowView(
                        event: event,
                        date: date,
                        isKeyboardSelected: isSelected,
                        detailPresentationRequest: detailRequest,
                        onDetailPresentationChange: { palette.eventDetailPresentationChanged(eventID: event.id, isShowing: $0) }
                    )
                    .simultaneousGesture(TapGesture().onEnded { session.select(entry: position) })
                }
            } else {
                AgendaPlaceholderRowView()
            }
        case .task(let task):
            CalendarTaskRowView(
                task: task,
                day: date,
                coordinator: taskCoordinator,
                isKeyboardSelected: isSelected,
                onComplete: { _ = taskCoordinator.actions.setCompleted(!task.isCompleted, taskID: task.id) },
                onSelect: { session.select(entry: position) }
            )
        }
    }
}

/// What the Search list scrolls to and reports as visible: a day, or a
/// result in it (positions in the index).
private enum SearchAnchor: Hashable {
    case day(Int)
    case entry(day: Int, position: Int)

    var day: Int {
        switch self {
        case .day(let day), .entry(let day, _): return day
        }
    }
}

/// Paging bookkeeping that mustn't redraw the list.
private final class PagingState {
    var isRestoring = false
}
