import Foundation
import Observation
import SwiftUI
import Domain

/// Owns all agenda-section paging state, separately from `CalendarViewModel`
/// (which owns only the month grid). That separation is what actually fixes
/// the click/switch-view lag: since this is a distinct `@Observable` object,
/// `AgendaListView` can read `store.sections` directly in its own body,
/// isolating its re-render scope from `CalendarViewModel`'s grid-only
/// properties (`days`, `visibleMonth`, `selectedDate`) — a mutation of one
/// no longer forces SwiftUI to re-diff the other's (much larger) view tree.
///
/// Starts with a small initial window and grows only on demand — via
/// `ensureLoaded(covering:)` (jump/navigation lands outside the loaded
/// range) or `loadMoreIfNeeded(nearTopOf:/nearBottomOf:)` (scrolling near
/// either loaded edge) — rather than fetching one large upfront window.
/// Knows nothing about EventKit or any other source's own caching; it only
/// calls `CalendarDataProviding.agendaSections(in:calendar:)`, a pure
/// range-in/sections-out contract, which is what makes this store itself
/// source-independent.
@MainActor
@Observable
package final class AgendaSectionStore {
    private let dataProvider: CalendarDataProviding
    private let calendar: Calendar

    package private(set) var sections: [AgendaDaySection] = []
    package private(set) var isLoadingAtTop = false
    package private(set) var isLoadingAtBottom = false

    private var loadedRange: DateInterval?
    private var inFlightRanges: [UUID: DateInterval] = [:]
    /// A navigation supersedes older navigation, paging and reload results.
    private var navigationGeneration = 0

    package init(dataProvider: CalendarDataProviding, calendar: Calendar) {
        self.dataProvider = dataProvider
        self.calendar = calendar
    }

    /// Called once at startup, and again after a full invalidate (`reload`).
    package func loadInitialWindow(around anchor: Date) async {
        navigationGeneration += 1
        let generation = navigationGeneration
        let start = calendar.date(byAdding: .day, value: -AppConfiguration.agendaInitialWindowBehindDays, to: anchor) ?? anchor
        let end = calendar.date(byAdding: .day, value: AppConfiguration.agendaInitialWindowAheadDays, to: anchor) ?? anchor
        await load(range: DateInterval(start: start, end: end), merging: false, navigation: generation)
        guard isCurrent(generation) else { return }
        insertPlaceholderIfNeeded(for: anchor)
    }

    /// Full invalidate + reload — for calendar-visibility toggles and
    /// `EKEventStoreChanged`-driven refreshes, where whatever's already
    /// loaded might now be stale/wrong.
    ///
    /// Refreshes the window that is already loaded, replacing its sections
    /// in one step. Emptying it first (as this used to) collapsed the list
    /// for a moment and threw the scroll position — e.g. every time a
    /// reminder was completed, since that too fires `EKEventStoreChanged`.
    /// Day identities don't change, so the list keeps its place.
    ///
    /// Only real differences are applied — a store change that touched no
    /// visible event (a reminder completed, another calendar edited) leaves
    /// the list untouched. With `animation`, what did change animates in
    /// place: events appear, disappear or update where they are, every other
    /// row keeps its identity.
    package func reload(around anchor: Date, animation: Animation? = nil) async {
        guard let range = loadedRange, !sections.isEmpty else {
            loadedRange = nil
            sections = []
            await loadInitialWindow(around: anchor)
            return
        }
        let generation = navigationGeneration
        let fetched = await dataProvider.agendaSections(in: range, calendar: calendar)
        guard isCurrent(generation), let retainedRange = loadedRange else { return }
        // The window may have grown while this was fetching: keep the rest.
        let outside = sections.filter { !Self.contains(range, $0.date, calendar: calendar) }
        let retained = (fetched + outside).filter { Self.contains(retainedRange, $0.date, calendar: calendar) }
        let refreshed = filled(deduplicated(retained), in: retainedRange)
        if refreshed != sections {
            if let animation {
                withAnimation(animation) { sections = refreshed }
            } else {
                sections = refreshed
            }
        }
        insertPlaceholderIfNeeded(for: anchor)
    }

    private static func contains(_ range: DateInterval, _ date: Date, calendar: Calendar) -> Bool {
        let day = calendar.startOfDay(for: date)
        return day >= calendar.startOfDay(for: range.start) && day <= calendar.startOfDay(for: range.end)
    }

    /// Ensures `date` is covered by the loaded window — the "jump to a
    /// far-away date" case (grid tap outside the window, chevron/keyboard
    /// month navigation, a search jump). No-op if already covered.
    package func ensureLoaded(covering date: Date) async {
        let day = calendar.startOfDay(for: date)
        if let loadedRange, loadedRange.start <= day, loadedRange.end >= day {
            // Loaded ranges are filled day by day, but a day between two
            // separately loaded ranges can still be missing its row.
            insertPlaceholderIfNeeded(for: day)
            return
        }

        let start = calendar.date(byAdding: .day, value: -AppConfiguration.agendaChunkDays, to: day) ?? day
        let end = calendar.date(byAdding: .day, value: AppConfiguration.agendaChunkDays, to: day) ?? day
        // Only a navigation that fetches supersedes work in flight; one that's
        // already covered (a step within the window) leaves it alone.
        navigationGeneration += 1
        let generation = navigationGeneration
        // Far from what's loaded, the jump's window replaces it: merged,
        // the loaded range would span the unfetched days between the two
        // (and treat them as loaded, so they never appeared).
        await load(range: DateInterval(start: start, end: end), merging: true, trim: .around(day), whenApart: .replace,
                   navigation: generation)
        guard isCurrent(generation) else { return }
        insertPlaceholderIfNeeded(for: day)
    }

    /// Scroll-driven infinite-load: extends the loaded window by another
    /// chunk once the visible edge is within `agendaEdgeLoadThresholdDays`
    /// of it.
    /// `isAtLoadedContentEdge`: true when the first/last *rendered*
    /// section (not just a date-proximity estimate) is the one currently
    /// visible — the day-threshold check alone can't fire for a sparse
    /// calendar, where the nearest section with events may be many days
    /// past `loadedRange`'s own edge (empty days never get a section).
    package func loadMoreIfNeeded(nearTopOf visibleDate: Date, isAtLoadedContentEdge: Bool = false) async {
        guard let extendedRange = topExtension(nearTopOf: visibleDate, isAtLoadedContentEdge: isAtLoadedContentEdge) else { return }
        isLoadingAtTop = true
        // Scrolling up: days far below are dropped in the same write.
        // Content below the viewport doesn't move what's on screen, and
        // the bottom paging loads them again on the way back down.
        let keepBefore = calendar.date(byAdding: .day, value: AppConfiguration.agendaKeptDaysBeyondVisible,
                                       to: calendar.startOfDay(for: visibleDate))
        await load(range: extendedRange, merging: true, trim: keepBefore.map(Trim.from))
        isLoadingAtTop = false
    }

    /// Whether scrolling at `visibleDate` would load another chunk above —
    /// lets the scroll side skip the whole load-and-correct cycle when
    /// nothing is due, instead of finding out after the fact.
    package func wouldLoadMore(nearTopOf visibleDate: Date, isAtLoadedContentEdge: Bool = false) -> Bool {
        topExtension(nearTopOf: visibleDate, isAtLoadedContentEdge: isAtLoadedContentEdge) != nil
    }

    private func topExtension(nearTopOf visibleDate: Date, isAtLoadedContentEdge: Bool) -> DateInterval? {
        guard let loadedRange else { return nil }
        let threshold = calendar.date(byAdding: .day, value: AppConfiguration.agendaEdgeLoadThresholdDays, to: loadedRange.start) ?? loadedRange.start
        guard isAtLoadedContentEdge || visibleDate <= threshold else { return nil }

        let newStart = calendar.date(byAdding: .day, value: -AppConfiguration.agendaChunkDays, to: loadedRange.start) ?? loadedRange.start
        let extendedRange = DateInterval(start: newStart, end: loadedRange.start)
        return isCovered(extendedRange) ? nil : extendedRange
    }

    package func loadMoreIfNeeded(nearBottomOf visibleDate: Date, isAtLoadedContentEdge: Bool = false) async {
        guard let extendedRange = bottomExtension(nearBottomOf: visibleDate, isAtLoadedContentEdge: isAtLoadedContentEdge) else { return }

        isLoadingAtBottom = true
        // Scrolling down: days far above are dropped in the same write
        // (the scroll side re-anchors on the visible day, as after a top
        // merge). `visibleDate` is the last visible day, so the kept
        // margin also covers the screen above it.
        let keepFrom = calendar.date(byAdding: .day, value: -(AppConfiguration.agendaKeptDaysBeyondVisible + 14),
                                     to: calendar.startOfDay(for: visibleDate))
        await load(range: extendedRange, merging: true, trim: keepFrom.map(Trim.before))
        isLoadingAtBottom = false
    }

    package func wouldLoadMore(nearBottomOf visibleDate: Date, isAtLoadedContentEdge: Bool = false) -> Bool {
        bottomExtension(nearBottomOf: visibleDate, isAtLoadedContentEdge: isAtLoadedContentEdge) != nil
    }

    private func bottomExtension(nearBottomOf visibleDate: Date, isAtLoadedContentEdge: Bool) -> DateInterval? {
        guard let loadedRange else { return nil }
        let threshold = calendar.date(byAdding: .day, value: -AppConfiguration.agendaEdgeLoadThresholdDays, to: loadedRange.end) ?? loadedRange.end
        guard isAtLoadedContentEdge || visibleDate >= threshold else { return nil }

        let newEnd = calendar.date(byAdding: .day, value: AppConfiguration.agendaChunkDays, to: loadedRange.end) ?? loadedRange.end
        let extendedRange = DateInterval(start: loadedRange.end, end: newEnd)
        return isCovered(extendedRange) ? nil : extendedRange
    }

    /// True when `date` already falls within the currently loaded window —
    /// i.e. `ensureLoaded(covering:)` would be a no-op. Lets a hot-path
    /// caller (a grid click) skip the async round trip entirely when
    /// there's nothing to actually load.
    package func isLoaded(_ date: Date) -> Bool {
        guard let loadedRange else { return false }
        let day = calendar.startOfDay(for: date)
        return loadedRange.start <= day && loadedRange.end >= day
    }

    /// Synchronous read of whatever's already loaded — for the single-day
    /// timeline view. Callers that need a date not yet loaded must
    /// `ensureLoaded(covering:)` first (returns `[]` otherwise, same as
    /// the old `CalendarViewModel.selectedDateEvents`'s empty-section
    /// fallback).
    package func events(onDate date: Date) -> [AgendaEventModel] {
        sections.first { calendar.isDate($0.date, inSameDayAs: date) }?.events ?? []
    }

    private func isCovered(_ range: DateInterval) -> Bool {
        if let loadedRange, loadedRange.start <= range.start, loadedRange.end >= range.end { return true }
        if inFlightRanges.values.contains(where: { $0.start <= range.start && $0.end >= range.end }) { return true }
        return false
    }

    /// Which far days a load drops once the agenda is over its limit.
    package enum Trim {
        /// Days from this one on (below the viewport).
        case from(Date)
        /// Days before this one (above the viewport).
        case before(Date)
        /// Navigation: up to 79 days before and 80 after the requested day.
        case around(Date)
    }

    /// What a merging load does when its range neither overlaps nor
    /// touches the loaded one — the loaded window must stay one unbroken
    /// run of days.
    package enum Apart {
        /// A jump: its window becomes the loaded one.
        case replace
        /// Paging from an edge that has since moved away (a jump landed
        /// while it was loading): dropped.
        case discard
    }

    private func load(range: DateInterval, merging: Bool, trim: Trim? = nil, whenApart: Apart = .discard,
                      navigation: Int? = nil) async {
        // A newer navigation must not be skipped because a superseded request
        // covers it: that request will be discarded when it finishes.
        if navigation == nil {
            guard !isCovered(range) else { return }
        } else if let loadedRange, loadedRange.start <= range.start, loadedRange.end >= range.end {
            return
        }
        let generation = navigation ?? navigationGeneration
        let requestID = UUID()
        inFlightRanges[requestID] = range
        let fetched = await dataProvider.agendaSections(in: range, calendar: calendar)
        inFlightRanges[requestID] = nil
        guard isCurrent(generation) else { return }

        let isApart = loadedRange.map { !touches($0, range) } ?? false
        if merging, isApart, whenApart == .discard { return }

        // One write per load (merged and filled together): each write
        // redraws the agenda while it's being scrolled.
        if merging, !sections.isEmpty, !isApart {
            merge(fetched, range: range, trim: trim)
        } else {
            sections = filled(deduplicated(fetched), in: range)
            loadedRange = range
        }
    }

    /// Whether `range` overlaps `loaded` or begins or ends the day next to it.
    private func touches(_ loaded: DateInterval, _ range: DateInterval) -> Bool {
        let loadedStart = calendar.startOfDay(for: loaded.start)
        let loadedEnd = calendar.startOfDay(for: loaded.end)
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: loadedStart) ?? loadedStart
        let dayAfter = calendar.date(byAdding: .day, value: 1, to: loadedEnd) ?? loadedEnd
        return calendar.startOfDay(for: range.start) <= dayAfter && calendar.startOfDay(for: range.end) >= dayBefore
    }

    /// `sections` with an empty section for every day of `range` that has
    /// none — computed, then assigned once by the caller.
    private func filled(_ sections: [AgendaDaySection], in range: DateInterval) -> [AgendaDaySection] {
        var result = sections
        let last = calendar.startOfDay(for: range.end)
        var day = calendar.startOfDay(for: range.start)
        var present = Set(sections.map { calendar.startOfDay(for: $0.date) })
        var added = false
        while day <= last {
            if present.insert(day).inserted {
                result.append(emptySection(for: day))
                added = true
            }
            // Adding a day (not 86 400 s) keeps DST days single.
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        if added { result.sort { $0.date < $1.date } }
        return result
    }

    private func merge(_ fetched: [AgendaDaySection], range: DateInterval, trim: Trim? = nil) {
        // Never assume upstream state is unique. Concurrent requests used to
        // be able to insert the same empty-day placeholder twice; dictionary
        // construction with `uniqueKeysWithValues` deliberately traps in
        // that situation. Normalize to calendar days and let fetched data
        // replace an older placeholder for the same day.
        var byDate: [Date: AgendaDaySection] = [:]
        for section in sections {
            byDate[calendar.startOfDay(for: section.date)] = section
        }
        for section in fetched {
            byDate[calendar.startOfDay(for: section.date)] = section
        }
        var merged = filled(byDate.values.sorted { $0.date < $1.date }, in: range)
        merged = trimmed(merged, trim: trim)
        sections = merged
        if let first = merged.first, let last = merged.last { loadedRange = DateInterval(start: first.date, end: last.date) }
    }

    /// Over the limit: scrolling drops the far side away from the viewport
    /// first (it pages back in); then the window is cut to the limit — toward
    /// the viewport's side, or centred on a navigation's day.
    private func trimmed(_ merged: [AgendaDaySection], trim: Trim?) -> [AgendaDaySection] {
        let limit = AppConfiguration.agendaMaxLoadedDays
        guard merged.count > limit else { return merged }
        var kept = merged
        switch trim {
        case .from(let cutoff)?:
            if let firstDropped = kept.firstIndex(where: { $0.date >= cutoff }), firstDropped > 0 { kept.removeSubrange(firstDropped...) }
        case .before(let cutoff)?:
            if let firstKept = kept.firstIndex(where: { $0.date >= cutoff }), firstKept > 0 { kept.removeSubrange(..<firstKept) }
        case .around?, nil:
            break
        }
        guard kept.count > limit else { return kept }
        let first: Int
        switch trim {
        case .before?: first = kept.count - limit
        case .around(let day)?:
            let anchor = kept.firstIndex { $0.date >= day } ?? kept.count - 1
            first = max(0, min(anchor - (limit - 1) / 2, kept.count - limit))
        case .from?, nil: first = 0
        }
        return Array(kept[first..<(first + limit)])
    }

    /// No newer navigation has superseded this work, and it wasn't cancelled.
    private func isCurrent(_ generation: Int) -> Bool { generation == navigationGeneration && !Task.isCancelled }

    private func deduplicated(_ values: [AgendaDaySection]) -> [AgendaDaySection] {
        var byDate: [Date: AgendaDaySection] = [:]
        for section in values {
            byDate[calendar.startOfDay(for: section.date)] = section
        }
        return byDate.values.sorted { $0.date < $1.date }
    }

    /// The agenda needs a "you are here" anchor even on a day with zero
    /// events — the same role `EventKitCalendarProvider` used to fill
    /// itself before this store took over "always include today/the
    /// target day" policy (see the protocol's doc comment history).
    private func insertPlaceholderIfNeeded(for date: Date) {
        let day = calendar.startOfDay(for: date)
        guard let loadedRange, Self.contains(loadedRange, day, calendar: calendar) else { return }
        guard !sections.contains(where: { calendar.isDate($0.date, inSameDayAs: day) }) else { return }

        sections.append(emptySection(for: day))
        sections.sort { $0.date < $1.date }
    }

    private func emptySection(for day: Date) -> AgendaDaySection {
        AgendaDaySection(
            date: day,
            events: [],
            isToday: calendar.isDateInToday(day)
        )
    }
}
