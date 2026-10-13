import Foundation
import Observation
import Domain
import UI
import TimeWhisper

extension SearchPaletteModel {
    // MARK: - Resolution

    /// Re-resolves for new query text. The previous actions stay until the
    /// new ones are ready, so rows don't flicker while typing.
    package func update(query: String) {
        resolution?.cancel()
        results.cancelPendingResolution()
        generation += 1
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clear()
            return
        }
        let current = generation
        let referenceDate = now()
        let calendar = self.calendar
        let lists = taskLists()
        resolution = Task { @MainActor [weak self] in
            guard let self else { return }
            // Operators (`from:`, `day:` …) make it a search: no Go to or
            // Create for "refinement day:today".
            let isSearchOnly = SearchQuerySyntax.parse(trimmed).hasOperators
            let calendars = isSearchOnly ? [] : await eventCalendars()
            async let temporal = isSearchOnly ? nil : findTemporal(trimmed, referenceDate, calendar)
            async let parsed = isSearchOnly ? [] : parse(trimmed, referenceDate, calendar, lists, calendars)
            let (found, candidates) = await (temporal, parsed)
            let intent = found.flatMap { TemporalPresentation.navigation($0, calendar: calendar) }
            let offered = intent == nil ? candidates : []
            let conflict = await conflict(for: offered)
            let parts: SearchQueryParts
            if isSearchOnly {
                parts = await SearchQueryResolver.resolve(trimmed, referenceDate: referenceDate, calendar: calendar)
            } else {
                parts = TemporalPresentation.searchParts(trimmed, found: found, calendar: calendar)
            }
            guard !Task.isCancelled, current == generation else { return }
            self.query = trimmed
            self.candidates = offered
            results.update(query: trimmed, resolvedParts: parts)
            apply(intent: intent, candidates: offered, lists: lists, calendars: calendars, conflict: conflict,
                  referenceDate: referenceDate)
        }
    }

    /// Waits for the resolution and creation in flight (tests).
    package func settle() async {
        await resolution?.value
        await creation?.value
        await overlapCheck?.value
    }

    /// The edited event's time against its days, as it changes; nothing
    /// for an all-day event.
    func checkEditOverlap() {
        overlapCheck?.cancel()
        guard let event = eventEdit?.eventDraft(calendar: calendar), !event.isAllDay else {
            editOverlap = nil
            return
        }
        overlapCheck = Task { @MainActor [weak self] in
            guard let self else { return }
            let found = EventConflict.overlap(start: event.start, end: event.end,
                                              against: await events(touching: event.start, event.end))
            guard !Task.isCancelled else { return }
            if found != editOverlap { editOverlap = found }
        }
    }

    func events(touching start: Date, _ end: Date) async -> [AgendaEventModel] {
        var events: [AgendaEventModel] = []
        var day = calendar.startOfDay(for: start)
        while day < end {
            events += await eventsOn(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return events
    }

    /// The new event's time against the days it touches (first
    /// occurrence only); nil when no event is offered or it's all day.
    private func conflict(for candidates: [QuickAddCandidate]) async -> EventConflict? {
        guard let event = candidates.compactMap({ candidate -> EventDraft? in
            if case .event(let draft) = candidate { return draft }; return nil
        }).first, !event.isAllDay else { return nil }
        return EventConflict.check(start: event.start, end: event.end, against: await events(touching: event.start, event.end))
    }

    private func apply(intent: SearchIntent?, candidates: [QuickAddCandidate], lists: [CalendarSource], calendars: [CalendarSource],
                       conflict: EventConflict? = nil, referenceDate: Date) {
        dateIntent = intent
        eventCalendarOptions = calendars
        actions = PaletteActions.build(dateIntent: intent, candidates: candidates, lists: lists, calendars: calendars,
                                       conflict: conflict,
                                       isSearchable: SearchSession.isSearchable(query),
                                       referenceDate: referenceDate, calendar: calendar,
                                       format: timeFormat(), dates: dates())
        chosen = actions.first(where: \.isEnabled).map { .action($0.kind) }
        resetQuickAdd()
    }

    package func clear() {
        isResultsViewShown = false
        resolution?.cancel()
        results.update(query: "")
        openChildEditor = nil
        isCommitting = false
        actions = []
        chosen = nil
        eventDetailRequest = nil
        presentedEventID = nil
        dateIntent = nil
        candidates = []
        query = ""
        resetQuickAdd()
    }

    /// A new query (or none): Quick Add starts over, collapsed.
    private func resetQuickAdd() {
        isRefining = false
        edit = nil
        eventEdit = nil
    }
}
