import Foundation
import Observation
import Domain
import UI

extension SearchPaletteModel {
    // MARK: - Resolution

    /// Re-resolves for new query text. The previous actions stay until the
    /// new ones are ready, so rows don't flicker while typing.
    package func update(query: String) {
        results.update(query: query)
        resolution?.cancel()
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
            let intent = isSearchOnly ? .freeTextSearch(trimmed) : await resolveDate(trimmed, referenceDate, calendar)
            // Strict date first; the task parser only runs when it says no.
            let calendars = isSearchOnly || intent.isNavigation ? [] : await eventCalendars()
            let task = isSearchOnly || intent.isNavigation || (lists.isEmpty && calendars.isEmpty)
                ? nil : await resolveTask(trimmed, referenceDate, calendar, lists, calendars)
            let conflict = await conflict(for: task, calendars: calendars, referenceDate: referenceDate)
            guard !Task.isCancelled, current == generation else { return }
            self.query = trimmed
            apply(intent: intent, task: task, lists: lists, calendars: calendars, conflict: conflict,
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
    private func conflict(for task: QuickAddDraft?, calendars: [CalendarSource], referenceDate: Date) async -> EventConflict? {
        guard let task, !calendars.isEmpty, QuickAddKindDecision.decide(task).kinds.contains(.event) else { return nil }
        let event = task.eventDraft(calendar: calendar, referenceDate: referenceDate)
        guard !event.isAllDay else { return nil }
        return EventConflict.check(start: event.start, end: event.end, against: await events(touching: event.start, event.end))
    }

    private func apply(intent: SearchIntent, task: QuickAddDraft?, lists: [CalendarSource], calendars: [CalendarSource],
                       conflict: EventConflict? = nil, referenceDate: Date) {
        dateIntent = intent.isNavigation ? intent : nil
        taskDraft = task
        eventCalendarOptions = calendars
        actions = PaletteActions.build(dateIntent: dateIntent, task: task, lists: lists, calendars: calendars,
                                       conflict: conflict,
                                       isSearchable: SearchSession.isSearchable(query),
                                       referenceDate: referenceDate, calendar: calendar,
                                       format: .current)
        // The first real action owns the selection; placeholders never do.
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
        taskDraft = nil
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
