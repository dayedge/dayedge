import EventKit
import Domain

/// The EventKit side. Occurrences are located like
/// `EventKitEventRemovalService`: a bounded fetch matching identifier,
/// calendar and exact start, never `event(withIdentifier:)` alone — and
/// writability and ownership are checked again right before writing.
@MainActor
package final class EventKitEventEditor: CalendarEventEditing {
    private let eventStore: EKEventStore

    package init(eventStore: EKEventStore) {
        self.eventStore = eventStore
    }

    package func writableCalendars() async -> [WritableCalendar] {
        let defaultID = eventStore.defaultCalendarForNewEvents?.calendarIdentifier
        return eventStore.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .map { WritableCalendar(identifier: $0.calendarIdentifier, title: $0.title,
                                    isDefault: $0.calendarIdentifier == defaultID, tint: RGBAColor($0.color),
                                    group: $0.source?.title ?? "") }
    }

    package func create(_ draft: EventDraft) async throws -> EventSnapshot {
        let calendar: EKCalendar?
        if let id = draft.calendarIdentifier {
            calendar = eventStore.calendar(withIdentifier: id)
        } else {
            calendar = eventStore.defaultCalendarForNewEvents
        }
        guard let calendar, calendar.allowsContentModifications else { throw EventEditError.noCalendar(nil) }
        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = draft.title
        event.startDate = draft.start
        event.endDate = draft.end
        event.isAllDay = draft.isAllDay
        event.location = draft.location
        event.notes = draft.notes
        if let rule = draft.recurrenceRule { event.recurrenceRules = [ReminderMapper.ekRule(from: rule)] }
        for alert in draft.alerts { event.addAlarm(CalendarEventMapper.alarm(for: alert)) }
        draft.details?.apply(to: event)
        try eventStore.save(event, span: .thisEvent, commit: true)
        Self.announceWrite(.write(before: nil, after: (calendar.calendarIdentifier, event.startDate, event.endDate),
                                  throughFuture: false))
        return Self.snapshot(event)
    }

    // swiftlint:disable:next cyclomatic_complexity - a check per EventChange field before writing it
    package func update(_ target: EventEditReference, _ change: EventChange, span: EventSpan) async throws -> (before: EventSnapshot, after: EventSnapshot) {
        let event = try writableOccurrence(target, forEditing: !change.isAlertsOnly)
        if let rules = Self.newRules(change), event.isDetached, !event.hasRecurrenceRules {
            return try changeRepeat(ofDetached: event, to: rules)
        }
        let before = Self.snapshot(event)
        var span = span
        let duration = event.endDate.timeIntervalSince(event.startDate)
        if let title = change.title { event.title = title }
        if let isAllDay = change.isAllDay { event.isAllDay = isAllDay }
        if let start = change.start {
            event.startDate = start
            event.endDate = change.end ?? start.addingTimeInterval(duration)
        } else if let end = change.end {
            event.endDate = end
        }
        if let location = change.location { event.location = location.isEmpty ? nil : location }
        if let notes = change.notes { event.notes = notes.isEmpty ? nil : notes }
        if let rules = Self.newRules(change) {
            // A rule belongs to the series: on a repeating event it changes
            // this and future events, as in Calendar.
            if event.hasRecurrenceRules { span = .futureEvents }
            event.recurrenceRules = rules.isEmpty ? nil : rules
        }
        if let id = change.calendarIdentifier, id != event.calendar.calendarIdentifier {
            guard let target = eventStore.calendar(withIdentifier: id), target.allowsContentModifications else {
                throw EventEditError.notWritable
            }
            event.calendar = target
        }
        if let alerts = change.alerts {
            for alarm in event.alarms ?? [] where alarm.structuredLocation == nil { event.removeAlarm(alarm) }
            for alert in alerts { event.addAlarm(CalendarEventMapper.alarm(for: alert)) }
        }
        try eventStore.save(event, span: span.eventKit, commit: true)
        Self.announceWrite(.write(before: (before.calendarIdentifier, before.start, before.end),
                                  after: (event.calendar.calendarIdentifier, event.startDate, event.endDate),
                                  throughFuture: span == .futureEvents))
        return (before, Self.snapshot(event))
    }

    package func delete(_ target: EventEditReference, span: EventSpan) async throws -> EventSnapshot {
        let event = try writableOccurrence(target, forEditing: false)
        let before = Self.snapshot(event)
        try eventStore.remove(event, span: span.eventKit, commit: true)
        Self.announceWrite(.write(before: (before.calendarIdentifier, before.start, before.end), after: nil,
                                  throughFuture: span == .futureEvents))
        return before
    }

    /// Editing needs the user's own event without attendees; deleting only
    /// a writable calendar.
    /// A detached occurrence (edited on its own) can't hold a rule — setting
    /// one saves without effect (measured). So do what Calendar does for
    /// "this and future events": end the series just before this occurrence,
    /// and carry on from it as a new event with the new rule (or none).
    /// The rules a change sets — `[]` to stop repeating — or nil if it
    /// doesn't touch the repeat.
    private static func newRules(_ change: EventChange) -> [EKRecurrenceRule]? {
        if let rule = change.recurrenceRule { return [ReminderMapper.ekRule(from: rule)] }
        guard let recurrence = change.recurrence, !recurrence.isCustom else { return nil }
        return ReminderMapper.rule(for: recurrence).map { [$0] } ?? []
    }

    private func changeRepeat(ofDetached occurrence: EKEvent, to rules: [EKRecurrenceRule]) throws -> (before: EventSnapshot, after: EventSnapshot) {
        let before = Self.snapshot(occurrence)
        let series = try seriesEvent(of: occurrence)

        let next = EKEvent(eventStore: eventStore)
        next.calendar = occurrence.calendar
        next.title = occurrence.title
        next.startDate = occurrence.startDate
        next.endDate = occurrence.endDate
        next.isAllDay = occurrence.isAllDay
        next.location = occurrence.location
        next.notes = occurrence.notes
        EventDetails(occurrence).apply(to: next)
        next.recurrenceRules = rules.isEmpty ? nil : rules

        // All or nothing: the store is shared, so a step left staged after a
        // failure would ride along with the next unrelated commit. `reset()`
        // drops it (and every fetched object — each write re-locates its own).
        do {
            if series.startDate >= occurrence.startDate {
                // It was the series' first occurrence: nothing earlier to keep.
                try eventStore.remove(series, span: .futureEvents, commit: false)
            } else if let rule = series.recurrenceRules?.first {
                series.recurrenceRules = [Self.rule(rule, endingBefore: occurrence.startDate)]
                try eventStore.save(series, span: .futureEvents, commit: false)
            }
            try eventStore.save(next, span: .thisEvent, commit: false)
            try eventStore.commit()
        } catch {
            eventStore.reset()
            throw error
        }
        // The series now ends before this occurrence and carries on as a new
        // one: everything from here on changed.
        Self.announceWrite(.write(before: (before.calendarIdentifier, before.start, before.end),
                                  after: (next.calendar.calendarIdentifier, next.startDate, next.endDate),
                                  throughFuture: true))
        return (before, Self.snapshot(next))
    }

    /// The series an occurrence belongs to: by its external identifier
    /// without the occurrence's "/RID=…" suffix (`CalendarEventMapper.seriesIdentifier`),
    /// in the occurrence's own calendar (an external id can repeat across
    /// accounts), and still writable.
    private func seriesEvent(of occurrence: EKEvent) throws -> EKEvent {
        guard let externalID = occurrence.calendarItemExternalIdentifier else { throw EventEditError.notFound }
        let seriesID = CalendarEventMapper.seriesIdentifier(externalID)
        let candidates = eventStore.calendarItems(withExternalIdentifier: seriesID).compactMap { $0 as? EKEvent }
        let calendarID = occurrence.calendar.calendarIdentifier
        let described = candidates.map {
            SeriesCandidate(calendarID: $0.calendar.calendarIdentifier, itemID: $0.calendarItemIdentifier, repeats: $0.hasRecurrenceRules)
        }
        guard let index = Self.seriesIndex(in: described, calendarID: calendarID, itemID: occurrence.calendarItemIdentifier) else {
            throw EventEditError.notFound
        }
        let series = candidates[index]
        guard series.calendar.allowsContentModifications else { throw EventEditError.notWritable }
        return series
    }

    package struct SeriesCandidate {
        package let calendarID: String
        package let itemID: String
        package let repeats: Bool

        package init(calendarID: String, itemID: String, repeats: Bool) {
            self.calendarID = calendarID
            self.itemID = itemID
            self.repeats = repeats
        }
    }

    /// Which candidate is the series: repeating, in the same calendar, and
    /// the same item as the occurrence when one says so.
    package nonisolated static func seriesIndex(in candidates: [SeriesCandidate], calendarID: String, itemID: String) -> Int? {
        let inCalendar = candidates.indices.filter { candidates[$0].repeats && candidates[$0].calendarID == calendarID }
        return inCalendar.first { candidates[$0].itemID == itemID } ?? inCalendar.first
    }

    /// The same rule, ending the moment before `date`.
    private static func rule(_ rule: EKRecurrenceRule, endingBefore date: Date) -> EKRecurrenceRule {
        EKRecurrenceRule(
            recurrenceWith: rule.frequency, interval: rule.interval,
            daysOfTheWeek: rule.daysOfTheWeek, daysOfTheMonth: rule.daysOfTheMonth,
            monthsOfTheYear: rule.monthsOfTheYear, weeksOfTheYear: rule.weeksOfTheYear,
            daysOfTheYear: rule.daysOfTheYear, setPositions: rule.setPositions,
            end: EKRecurrenceEnd(end: date.addingTimeInterval(-1))
        )
    }

    /// Tell the event sources: refresh now, don't wait for macOS to say so.
    /// With a scope, the index refetches exactly what was touched.
    package nonisolated static func announceWrite(_ scope: CalendarWriteScope? = nil) {
        CalendarWriteScope.announce(scope)
    }

    private func writableOccurrence(_ target: EventEditReference, forEditing: Bool) throws -> EKEvent {
        let calendars = eventStore.calendar(withIdentifier: target.calendarIdentifier).map { [$0] }
        let predicate = eventStore.predicateForEvents(
            withStart: target.occurrenceStart.addingTimeInterval(-60),
            end: target.occurrenceEnd.addingTimeInterval(60),
            calendars: calendars
        )
        guard let event = eventStore.events(matching: predicate).first(where: {
            $0.eventIdentifier == target.eventIdentifier
                && $0.calendar.calendarIdentifier == target.calendarIdentifier
                && $0.startDate == target.occurrenceStart
        }) else { throw EventEditError.notFound }
        guard event.calendar.allowsContentModifications else { throw EventEditError.notWritable }
        if forEditing {
            guard !CalendarEventMapper.isInvitation(event) else { throw EventEditError.invitation(from: event.organizer?.name) }
            guard (event.attendees ?? []).isEmpty else { throw EventEditError.meeting }
        }
        return event
    }

    private static func snapshot(_ event: EKEvent) -> EventSnapshot {
        EventSnapshot(
            eventIdentifier: event.eventIdentifier ?? "",
            calendarIdentifier: event.calendar.calendarIdentifier,
            calendarTitle: event.calendar.title,
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            location: event.location,
            notes: event.notes,
            hasAttendees: !(event.attendees ?? []).isEmpty,
            isRecurring: CalendarEventMapper.isRecurring(event),
            alerts: CalendarEventMapper.alerts(from: event.alarms),
            details: EventDetails(event)
        )
    }
}

extension EventSpan {
    package var eventKit: EKSpan { self == .thisEvent ? .thisEvent : .futureEvents }
}
