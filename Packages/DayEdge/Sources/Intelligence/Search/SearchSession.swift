import Foundation
import Observation
import Domain

/// One live search, shared by the palette preview and the Search view.
///
/// Holds only a lightweight `SearchIndex` of everything that matched
/// (event row ids and starts; tasks are in memory anyway) and full events
/// for the days the Search view renders (`SearchDayPaging`) — loaded by id
/// off the main thread when that window opens or pages, evicted outside it,
/// and never touched while scrolling inside it. Follows the query (three letters,
/// debounced, stale results dropped) and calendar / task changes.
@MainActor
@Observable
package final class SearchSession {
    package private(set) var query = ""
    package private(set) var index = SearchIndex.empty
    /// The query has a searchable word but its index isn't in yet.
    package private(set) var isPending = false
    /// Loaded events of the window, by index row id.
    package private(set) var events: [Int64: AgendaEventModel] = [:]
    /// The Search view's keyboard selection: a position in `index.entries`.
    package private(set) var selectedEntry: Int?
    /// Bumped for each new query's index (not for refreshes) — the Search
    /// view scrolls back to where browsing starts on it.
    package private(set) var revision = 0
    /// The query split into words and a date range ("standup tomorrow").
    package private(set) var parts = SearchQueryParts.plain("")
    /// The palette's top results, most relevant first (positions in
    /// `index`); nil when no ranking is wired (nearest today instead).
    private var rankedPreview: [Int]?

    /// The preview under the palette's Search row.
    package static let previewCount = 3
    /// Candidates per list (best scored, nearest, nearest by title) read
    /// for ranking the preview.
    package static let rankedCandidates = 50
    /// Letters/digits a query needs before it's searched.
    package nonisolated static let minimumCharacters = SearchQueryParts.minimumCharacters

    @ObservationIgnored package var searchMatches: (SearchQueryParts) async -> [SearchMatch] = { _ in [] }
    /// The best event matches for the preview; nil ranks nothing.
    @ObservationIgnored package var searchRanked: ((SearchQueryParts) async -> [RankedMatch])?
    /// Resolves the query: operators and date phrases (`SearchQueryResolver`).
    @ObservationIgnored package var parseQuery: (String) async -> SearchQueryParts = { .plain($0) }
    @ObservationIgnored package var loadEvents: ([Int64]) async -> [Int64: AgendaEventModel] = { _ in [:] }
    @ObservationIgnored package var tasks: () -> [TaskItem] = { [] }
    @ObservationIgnored package var calendar: Calendar = .autoupdatingCurrent
    @ObservationIgnored package var now: () -> Date = { Date() }
    @ObservationIgnored package var debounce: Duration = .milliseconds(200)

    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var loads: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var inFlight: Set<Int64> = []
    /// The entries of the rendered days, nil before any.
    @ObservationIgnored private var window: Range<Int>?

    /// Whether `query` has enough to search for (three letters or digits).
    package nonisolated static func isSearchable(_ query: String) -> Bool { SearchQueryParts.isSearchable(query) }

    package var hasQuery: Bool { Self.isSearchable(query) }
    package var total: Int { index.total }

    /// "24 results · March 2026" — events and tasks together, live.
    package var summary: String {
        if isPending && total == 0 { return L10n.tr("searchsession.searching", "Searching…") }
        let count = total == 0 ? L10n.tr("searchsession.no.matches", "No matches") : L10n.tr("search.results.count", "\(total) results")
        return [count, parts.label].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: - Query

    package func update(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != self.query else { return }
        self.query = trimmed
        pending?.cancel()
        guard Self.isSearchable(trimmed) else {
            reset()
            return
        }
        isPending = true
        let delay = debounce
        pending = Task { @MainActor [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard let self, !Task.isCancelled else { return }
            await rebuild(keepingWindow: false)
        }
    }

    /// The calendar or the tasks changed: the same query, a fresh index;
    /// the window reloads where it is.
    package func refresh() {
        guard hasQuery, !isPending else { return }
        pending = Task { @MainActor [weak self] in await self?.rebuild(keepingWindow: true) }
    }

    /// Waits for the index and the loads in flight (tests).
    package func settle() async {
        await pending?.value
        // Completions remove themselves while this suspends. Await a stable
        // snapshot rather than keeping a dictionary iteration across awaits.
        for load in Array(loads.values) { await load.value }
    }

    private func reset() {
        generation += 1
        index = .empty
        parts = .plain(query)
        rankedPreview = nil
        selectedEntry = nil
        events = [:]
        inFlight = []
        window = nil
        isPending = false
    }

    /// Matches off the main thread; tasks (in memory) here. The events
    /// the result opens on (and the preview) are loaded *before* the new
    /// index is published, and models still matching are kept — so typing
    /// never flashes placeholders. A refresh reloads the window and swaps
    /// it in at once. A result for a query that has since changed is
    /// dropped.
    private func rebuild(keepingWindow: Bool) async {
        let query = self.query
        let parts = await parseQuery(query)
        guard !Task.isCancelled, query == self.query else { return }
        // Only a date ("tomorrow") is Go to's, not a search.
        guard parts.isSearchable else {
            reset()
            self.parts = parts
            return
        }
        let candidates = parts.includesTasks ? tasks().filter { Self.matches($0, parts) } : []
        async let matchesRead = parts.includesEvents ? searchMatches(parts) : []
        async let rankedRead = parts.includesEvents ? searchRanked?(parts) : []
        let (matches, ranked) = await (matchesRead, rankedRead)
        guard !Task.isCancelled, query == self.query else { return }
        let now = now()
        let next = SearchIndex.build(matches: matches, tasks: candidates, now: now, calendar: calendar,
                                     anchorsAtStart: parts.interval.map { $0.start != .distantPast } ?? false)
        let top = ranked.map { ranked in
            Self.positions(of: SearchRelevance.top(events: ranked, tasks: candidates, query: parts.rankingText, now: now,
                                                   limit: Self.previewCount), in: next)
        }

        let opening: Range<Int>
        if keepingWindow, let window {
            opening = window.clamped(to: 0..<next.total)
        } else {
            opening = Self.entries(of: SearchDayPaging.opening(at: next.anchorDayIndex, dayCount: next.days.count), in: next)
        }
        let wanted = Set((Self.previewPositions(in: next, ranked: top) + Array(opening)).compactMap { next.entries[$0].eventID })
        // A refresh reloads (events may have changed); a new query reuses.
        let missing = keepingWindow ? Array(wanted) : wanted.filter { events[$0] == nil }
        let loaded = missing.isEmpty ? [:] : await loadEvents(missing)
        guard !Task.isCancelled, query == self.query else { return }

        generation += 1
        inFlight = []
        let kept = keepingWindow ? [:] : events.filter { id, _ in next.eventPositions[id] != nil }
        events = kept.merging(loaded) { _, new in new }
        index = next
        self.parts = parts
        rankedPreview = top
        isPending = false
        if keepingWindow {
            selectedEntry = selectedEntry.map { min($0, index.total - 1) }.flatMap { $0 >= 0 ? $0 : nil }
        } else {
            window = opening
            selectedEntry = index.anchorEntryIndex
            revision += 1
        }
    }

    /// A task matches its words (title or notes), its `subject:` words (in
    /// the title) and the date range (by due date).
    package nonisolated static func matches(_ task: TaskItem, _ parts: SearchQueryParts) -> Bool {
        let words = TaskSearch.words(in: parts.text)
        if !words.isEmpty, !TaskSearch.matches(task, words: words) { return false }
        if let subject = parts.subject {
            let title = TaskItem(id: task.id, title: task.title, listID: task.listID)
            guard TaskSearch.matches(title, query: subject) else { return false }
        }
        if let interval = parts.interval {
            guard let due = task.dueDate, interval.start <= due, due < interval.end else { return false }
        }
        return !words.isEmpty || parts.subject != nil || parts.interval != nil
    }

    // MARK: - Window

    /// The days the Search view renders (it pages them like the agenda):
    /// their events are loaded and the rest evicted — once per page, as the
    /// agenda loads a chunk, so scrolling within them writes nothing and
    /// redraws nothing.
    package func show(days: Range<Int>) {
        // From a view still showing earlier results: clamped, or ignored.
        let target = Self.entries(of: days, in: index)
        guard !target.isEmpty, target != window else { return }
        window = target
        evict(keeping: target)
        load(Array(target))
    }

    /// The entries of `days` (positions in `index.days`).
    private static func entries(of days: Range<Int>, in index: SearchIndex) -> Range<Int> {
        let days = days.clamped(to: index.days.indices)
        guard let first = days.first, let last = days.last else { return 0..<0 }
        return index.days[first].range.lowerBound..<index.days[last].range.upperBound
    }

    /// The loaded event for an entry, nil while it's loading.
    package func event(for entry: SearchIndex.Entry) -> AgendaEventModel? {
        entry.eventID.flatMap { events[$0] }
    }

    private func evict(keeping target: Range<Int>) {
        let keep = Set(previewPositions).union(target)
        let kept = events.filter { id, _ in index.eventPositions[id].map(keep.contains) ?? false }
        // Only a real change is written: every write redraws the list.
        if kept.count != events.count { events = kept }
    }

    private func load(_ positions: [Int]) {
        let ids = positions.compactMap { index.entries.indices.contains($0) ? index.entries[$0].eventID : nil }
            .filter { events[$0] == nil && !inFlight.contains($0) }
        guard !ids.isEmpty else { return }
        inFlight.formUnion(ids)
        let current = generation
        let request = UUID()
        loads[request] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { loads[request] = nil }
            let loaded = await loadEvents(ids)
            guard current == generation else { return }
            inFlight.subtract(ids)
            // The reader may have moved while these events were loading.
            // Keep the current window and preview only; a read that is still
            // in flight remains useful if the reader returns to its window.
            let keep = Set(previewPositions).union(window ?? 0..<0)
            let wanted = loaded.filter { id, _ in self.index.eventPositions[id].map(keep.contains) ?? false }
            if !wanted.isEmpty { events.merge(wanted) { _, new in new } }
        }
    }

    // MARK: - Selection (the Search view)

    /// ↑ / ↓ through every result, clamped at the ends.
    package func select(_ delta: Int) {
        guard index.total > 0 else { return }
        let current = selectedEntry ?? index.anchorEntryIndex ?? 0
        selectedEntry = min(max(current + delta, 0), index.total - 1)
    }

    package func select(entry: Int) {
        guard index.entries.indices.contains(entry) else { return }
        selectedEntry = entry
    }

    /// The selected result, once its event is loaded.
    package var selectedRowItem: SearchResultRowItem? { selectedEntry.flatMap(rowItem(at:)) }

    // MARK: - Preview

    /// The entries the palette preview shows: the most relevant three, or
    /// without a ranking three around where browsing starts, slid back when
    /// fewer follow.
    private var previewPositions: [Int] { Self.previewPositions(in: index, ranked: rankedPreview) }

    private static func previewPositions(in index: SearchIndex, ranked: [Int]?) -> [Int] {
        if let ranked { return ranked }
        guard let anchor = index.anchorEntryIndex else { return [] }
        let start = max(0, min(anchor, index.total - previewCount))
        return Array(start..<min(start + previewCount, index.total))
    }

    private static func positions(of entries: [SearchIndex.Entry], in index: SearchIndex) -> [Int] {
        entries.compactMap { entry in
            if let id = entry.eventID { return index.eventPositions[id] }
            guard case .task(let task) = entry else { return nil }
            return index.entries.firstIndex { if case .task(let other) = $0 { other.id == task.id } else { false } }
        }
    }

    /// The palette preview's rows (events once loaded).
    package var preview: [SearchResultRowItem] {
        previewPositions.compactMap(rowItem(at:))
    }

    package func rowItem(at position: Int) -> SearchResultRowItem? {
        guard index.entries.indices.contains(position) else { return nil }
        let entry = index.entries[position]
        let day = index.dayIndex(containing: position).flatMap { index.days[$0].day }
        let result: SearchResult
        switch entry {
        case .event(let id, _, _):
            guard let event = events[id] else { return nil }
            result = .event(event)
        case .task(let task):
            result = .task(task)
        }
        let today = calendar.startOfDay(for: now())
        return SearchResultRowItem(result: result, day: day, isToday: day == today,
                                   isOutsideCurrentYear: day.map { calendar.component(.year, from: $0) != calendar.component(.year, from: today) } ?? false)
    }
}
