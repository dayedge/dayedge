import Foundation
import Domain

/// `event_details`: one event in full — place, organizer, the user's own
/// response, every attendee with theirs, and the notes. The list tools stay
/// compact; this is fetched only when the conversation needs it.
package enum EventDetailsTool {
    package static let maxAttendees = 25
    package static let maxNoteCharacters = 1_200
    /// Where a title is looked for by default: a week back, a month ahead.
    package static let defaultDaysBack = 7
    package static let defaultDaysAhead = 30

    package static func make(_ context: AssistantToolContext) -> AssistantTool {
        .answering(
            name: "event_details",
            description: "One event in full: attendees and their responses, the user's own response, organizer, place and notes.",
            parameters: [
                .init(name: "event", kind: .string, description: "The event's reference like E1, or its title."),
                .init(name: "when", kind: .string,
                      description: "Where to look for a title: \(AssistantWhen.accepted). Default: a week back to a month ahead.",
                      isRequired: false)
            ]
        ) { arguments in
            let name = try arguments.string("event")
            var range: DateInterval?
            if let when = arguments.optionalString("when") { range = try await AssistantWhen.resolve(when, context: context) }
            return try await answer(event: name, in: range, context: context)
        }
    }

    package static func answer(event name: String, in requested: DateInterval?, context: AssistantToolContext) async throws -> String {
        switch try await find(name, in: requested, context: context) {
        case .found(let event, let day): return describe(event, day: day, context: context)
        case .none: return "No event matching “\(name)”."
        case .several(let matches):
            var listing = AssistantListing(maxLines: context.maxLines)
            listing.append("Several events match “\(name)”; which one?")
            for match in matches { listing.append(context.eventLine(match.event, day: match.day, showsDay: true)) }
            return context.listing(listing)
        }
    }

    // MARK: - Finding the event

    package struct Occurrence {
        package let event: AgendaEventModel
        package let day: Date
    }

    package enum Match {
        case found(AgendaEventModel, day: Date)
        case none
        case several([Occurrence])
    }

    /// A reference ("E1", "[[E1]]") first; then the title in the period.
    /// Many occurrences of one repeating event resolve to the current or
    /// next one rather than a question.
    package static func find(_ name: String, in requested: DateInterval?, context: AssistantToolContext) async throws -> Match {
        try Task.checkCancellation()
        let trimmed = name.trimmingCharacters(in: CharacterSet(charactersIn: "[] ").union(.whitespacesAndNewlines))
        if case .event(let reference)? = context.references.reference(for: trimmed),
           let event = try await AssistantEventLookup.event(id: reference.id, on: reference.day, context: context) {
            return .found(event, day: reference.day)
        }

        // One operation-time snapshot makes selection consistent even when a
        // long range crosses an occurrence's end while it is being scanned.
        let now = context.now()
        let range = requested ?? defaultRange(now: now, context: context)
        let needle = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard !needle.isEmpty else { return .none }
        var matches = Occurrences(now: now)
        try await AssistantEventLookup.scan(in: range, context: context) { section in
            for event in section.events where event.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(needle) {
                matches.append(Occurrence(event: event, day: section.date))
            }
        }
        return matches.result
    }

    private struct Occurrences {
        let now: Date
        var candidates = AssistantCandidates<Occurrence>()
        var titlesDiffer = false
        var currentOrNext: Occurrence?
        var last: Occurrence?

        mutating func append(_ occurrence: Occurrence) {
            if let first = candidates.items.first, first.event.title != occurrence.event.title { titlesDiffer = true }
            candidates.append(occurrence)
            if currentOrNext == nil, (occurrence.event.endDate ?? occurrence.day) >= now { currentOrNext = occurrence }
            last = occurrence
        }

        var result: Match {
            guard let first = candidates.items.first, let last else { return .none }
            if candidates.count == 1 { return .found(first.event, day: first.day) }
            if titlesDiffer { return .several(candidates.items) }
            let selected = currentOrNext ?? last
            return .found(selected.event, day: selected.day)
        }
    }

    // MARK: - The answer

    package static func describe(_ event: AgendaEventModel, day: Date, context: AssistantToolContext) -> String {
        let calendar = context.calendar
        var lines = [context.eventLine(event, day: day, showsDay: true)]

        var when = AssistantFormat.dayTitle(day, calendar: calendar)
        when += event.isAllDay ? ", all day" : ", \(AssistantFormat.timeRange(event))"
        if event.isRecurring { when += " · repeats" }
        lines.append("When: \(when)")
        if let place = event.subtitle, !place.isEmpty { lines.append("Where: \(place)") }
        if let service = event.videoService { lines.append("Video call: \(service.displayName)") } else if event.videoURL != nil { lines.append("Video call: yes") }
        lines.append("Calendar: \(event.calendarName)")
        if let organizer = event.organizerName, !organizer.isEmpty { lines.append("Organizer: \(organizer)") }
        if let history = history(event, calendar: calendar) { lines.append(history) }
        lines.append("Your response: \(myResponse(event))")

        if event.attendees.isEmpty {
            lines.append("Attendees: none listed.")
        } else {
            lines.append("Attendees (\(event.attendees.count)): \(tally(event.attendees))")
            let sorted = event.attendees.sorted { order($0, event) < order($1, event) }
            lines += sorted.prefix(maxAttendees).map { "- \(attendeeLine($0, event: event))" }
            if event.attendees.count > maxAttendees { lines.append("…and \(event.attendees.count - maxAttendees) more") }
        }

        if let notes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            lines.append("Notes:")
            lines.append(notes.count > maxNoteCharacters ? String(notes.prefix(maxNoteCharacters)) + " …(notes shortened)" : notes)
        } else {
            lines.append("Notes: none.")
        }
        // Attendee and note lines aren't items, so no line cap here — the
        // attendee list and notes are capped themselves.
        let text = lines.joined(separator: "\n")
        return context.showsReferences ? text + "\n" + AssistantFormat.referenceHint : text
    }

    /// "Created 21 Sep 2026 14:05 · Last changed 23 Sep 2026 09:12" — for a
    /// repeating event these belong to the whole series.
    private static func history(_ event: AgendaEventModel, calendar: Calendar) -> String? {
        var parts: [String] = []
        if let created = event.createdAt { parts.append("Created \(AssistantFormat.stamp(created, calendar: calendar))") }
        if let modified = event.modifiedAt, modified != event.createdAt {
            parts.append("Last changed \(AssistantFormat.stamp(modified, calendar: calendar))")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ") + (event.isRecurring ? " (the whole series)" : "")
    }

    package static func status(_ status: EventAttendee.Status) -> String {
        switch status {
        case .accepted: return "accepted"
        case .declined: return "declined"
        case .tentative: return "maybe"
        case .pending: return "not responded"
        case .unknown: return "unknown"
        }
    }

    private static func myResponse(_ event: AgendaEventModel) -> String {
        if let mine = event.myResponseStatus { return status(mine) }
        return event.attendees.isEmpty ? "your own event, no invitees" : "you're not on the attendee list (likely the organizer)"
    }

    /// "3 accepted, 1 maybe, 1 not responded" — in a fixed order.
    private static func tally(_ attendees: [EventAttendee]) -> String {
        let order: [EventAttendee.Status] = [.accepted, .tentative, .pending, .declined, .unknown]
        return order.compactMap { kind in
            let count = attendees.filter { $0.status == kind }.count
            return count == 0 ? nil : "\(count) \(status(kind))"
        }.joined(separator: ", ")
    }

    private static func attendeeLine(_ attendee: EventAttendee, event: AgendaEventModel) -> String {
        var name = attendee.name
        if name.isEmpty || name == "Unknown", let email = attendee.email { name = email }
        var tags: [String] = []
        if attendee.isCurrentUser { tags.append("you") }
        if isOrganizer(attendee, event) { tags.append("organizer") }
        let label = tags.isEmpty ? name : "\(name) (\(tags.joined(separator: ", ")))"
        return "\(label) · \(status(attendee.status))"
    }

    private static func isOrganizer(_ attendee: EventAttendee, _ event: AgendaEventModel) -> Bool {
        guard let organizer = event.organizerName, !organizer.isEmpty else { return false }
        return attendee.name == organizer
    }

    /// You first, then the organizer, then everyone else as listed.
    private static func order(_ attendee: EventAttendee, _ event: AgendaEventModel) -> Int {
        if attendee.isCurrentUser { return 0 }
        return isOrganizer(attendee, event) ? 1 : 2
    }

    private static func defaultRange(now: Date, context: AssistantToolContext) -> DateInterval {
        let calendar = context.calendar
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -defaultDaysBack, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: defaultDaysAhead + 1, to: today) ?? today
        return DateInterval(start: start, end: end)
    }
}
