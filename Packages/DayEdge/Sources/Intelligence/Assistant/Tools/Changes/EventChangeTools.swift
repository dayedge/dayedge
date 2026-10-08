import SwiftUI
import Domain
import UI

/// `create_event`, `update_event`, `delete_event` — one occurrence, on
/// calendars the user can change, never someone else's invitation.
package enum EventChangeTools {
    package static let eventArgument = "The event: its reference from a result (like E2), or its exact title."
    package static let whenArgument = "Where to look for it by title: \(AssistantWhen.accepted). Default: the last week and next two months."
    package static let defaultMinutes = 60

    package static func make(_ context: AssistantToolContext) -> [AssistantTool] {
        [create(context), update(context), delete(context)]
    }

    // MARK: - create_event

    package static func create(_ context: AssistantToolContext) -> AssistantTool {
        .answering(
            name: "create_event",
            description: context.brief("Create a calendar event. The user approves it in the app before it's created.", "Create a calendar event."),
            parameters: context.parameters([
                .init(name: "title", kind: .string, description: "The event's title."),
                .init(name: "start", kind: .string,
                      description: context.brief("When it starts: \(AssistantMoment.accepted). A day without a time makes an all-day event.",
                                                 "Day and time, e.g. friday 15:00."))
            ], optional: [
                .init(name: "end", kind: .string, description: "When it ends (a time, or a day and time). Omit to use duration_minutes.", isRequired: false),
                .init(name: "duration_minutes", kind: .integer, description: "Length in minutes when there's no end. Default 60.", isRequired: false),
                .init(name: "calendar", kind: .string, description: "The calendar's name. Omit for the default calendar.", isRequired: false),
                .init(name: "location", kind: .string, description: "Where.", isRequired: false),
                .init(name: "notes", kind: .string, description: "Notes.", isRequired: false)
            ])
        ) { arguments in
            guard let changes = context.changes else { return "Changes aren't available here." }
            let title = try arguments.string("title").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return "An event needs a title." }
            let calendar = context.calendar
            let start = try await AssistantMoment.resolve(try arguments.string("start"), context: context)
            let isAllDay = !start.hasTime
            let end = try await endDate(arguments, start: start, context: context)
            guard end > start.date else { return "The end is before the start. Ask the user for the right times." }

            let target: WritableCalendar
            switch targetCalendar(arguments, in: await changes.eventCalendars()) {
            case .success(let calendar): target = calendar
            case .failure(let refusal): return refusal.text
            }

            let draft = EventDraft(title: title, start: start.date, end: end, isAllDay: isAllDay,
                                   calendarIdentifier: target.identifier,
                                   location: arguments.optionalString("location").flatMap(TaskChangeTools.nonEmpty),
                                   notes: arguments.optionalString("notes").flatMap(TaskChangeTools.nonEmpty))
            let when = ChangeRunner.span(start: start.date, end: end, isAllDay: isAllDay, now: context.now(), calendar: calendar, format: context.timeFormat())
            let proposal = ChangeProposal(
                kind: .createEvent,
                subject: ChangeSubject(marker: .dot(target.color), title: title,
                                       detail: ChangeRunner.joined(when, target.title, draft.location)),
                offersAlwaysAllow: context.offersAlwaysAllow
            )
            return await ChangeRunner.run(proposal, context: context) {
                let created = try await changes.createEvent(draft)
                return .init(
                    text: L10n.tr("eventchangetools.created", "Created “\(String(describing: created.title))”"),
                    detail: ChangeRunner.joined(when, created.calendarTitle),
                    undo: { _ = try await changes.deleteEvent(created.reference) },
                    report: "Done — created:\n" + (await line(for: created, context: context) ?? "event \(when) \(created.title)")
                )
            }
        }
    }

    /// The new event's end: the next day for an all-day event, the `end`
    /// argument if given, else the start plus `duration_minutes`.
    private static func endDate(_ arguments: AssistantToolArguments, start: AssistantMoment,
                                context: AssistantToolContext) async throws -> Date {
        if !start.hasTime {
            return context.calendar.date(byAdding: .day, value: 1, to: start.date) ?? start.date
        }
        if let endText = arguments.optionalString("end").flatMap(TaskChangeTools.nonEmpty) {
            return try await AssistantMoment.resolve(endText, on: start.date, context: context).date
        }
        let minutes = arguments.integer("duration_minutes", in: 5...(14 * 1440)) ?? defaultMinutes
        return start.date.addingTimeInterval(Double(minutes) * 60)
    }

    /// The `calendar` argument's calendar, or the default one.
    private static func targetCalendar(_ arguments: AssistantToolArguments,
                                       in calendars: [WritableCalendar]) -> Result<WritableCalendar, Refusal> {
        if let name = arguments.optionalString("calendar").flatMap(TaskChangeTools.nonEmpty) {
            guard let match = AssistantTargetResolver.titleMatches(name, in: calendars, title: \.title).first else {
                let names = calendars.map(\.title).joined(separator: ", ")
                return .failure(Refusal(text: "There's no calendar called “\(name)” that can be changed. Calendars: \(names)."))
            }
            return .success(match)
        }
        guard let fallback = calendars.first(where: \.isDefault) ?? calendars.first else {
            return .failure(Refusal(text: "There's no calendar that can be changed."))
        }
        return .success(fallback)
    }

    // MARK: - update_event

    // swiftlint:disable:next cyclomatic_complexity function_body_length - one branch per optional argument the model may pass
    package static func update(_ context: AssistantToolContext) -> AssistantTool {
        .answering(
            name: "update_event",
            description: context.brief("Move or rename one event (one occurrence of a repeating one). Only pass what changes; "
                                       + "moving keeps its length. The user approves it in the app.",
                                       "Move or rename an event."),
            parameters: context.parameters([
                .init(name: "event", kind: .string, description: context.brief(eventArgument, "The event's title.")),
                .init(name: "start", kind: .string,
                      description: context.brief("New start: \(AssistantMoment.accepted), or just a time to keep its day.", "New time, or day and time."),
                      isRequired: false),
                .init(name: "title", kind: .string, description: "New title.", isRequired: false)
            ], optional: [
                .init(name: "when", kind: .string, description: whenArgument, isRequired: false),
                .init(name: "end", kind: .string, description: "New end time.", isRequired: false),
                .init(name: "location", kind: .string, description: "New location ('none' to remove it).", isRequired: false)
            ])
        ) { arguments in
            guard let changes = context.changes else { return "Changes aren't available here." }
            let found = try await AssistantTargetResolver.event(try arguments.string("event"), when: arguments.optionalString("when"), context: context)
            guard case .found(let event) = found else { return TaskChangeTools.unresolved(found) }
            let reference: EventEditReference
            switch editable(event, forEditing: true) {
            case .success(let value): reference = value
            case .failure(let message): return message.text
            }
            guard let oldStart = event.startDate, let oldEnd = event.endDate else { return "That event has no time to change." }
            let calendar = context.calendar
            let now = context.now()

            var change = EventChange()
            var fields: [ChangeField] = []
            var newStart = oldStart
            var newEnd = oldEnd
            if let startText = arguments.optionalString("start").flatMap(TaskChangeTools.nonEmpty) {
                let moment = try await AssistantMoment.resolve(startText, on: oldStart, context: context)
                if moment.hasTime {
                    newStart = moment.date
                } else {
                    // A new day, same time of day.
                    let time = calendar.dateComponents([.hour, .minute], from: oldStart)
                    newStart = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: moment.date) ?? moment.date
                }
                newEnd = newStart.addingTimeInterval(oldEnd.timeIntervalSince(oldStart))
                change.start = newStart
            }
            if let endText = arguments.optionalString("end").flatMap(TaskChangeTools.nonEmpty) {
                newEnd = try await AssistantMoment.resolve(endText, on: newStart, context: context).date
                change.end = newEnd
            }
            guard newEnd > newStart else { return "The end would be before the start. Ask the user for the right times." }
            if change.start != nil || change.end != nil {
                fields.append(ChangeField(
                    label: "Time",
                    before: ChangeRunner.span(start: oldStart, end: oldEnd, isAllDay: event.isAllDay, now: now, calendar: calendar, format: context.timeFormat()),
                    after: ChangeRunner.span(start: newStart, end: newEnd, isAllDay: event.isAllDay, now: now, calendar: calendar, format: context.timeFormat()),
                    assistantAfter: ChangeRunner.span(start: newStart, end: newEnd, isAllDay: event.isAllDay, now: now, calendar: calendar,
                                                      format: .twentyFourHour, locale: Locale(identifier: "en"))
                ))
            }
            if let title = arguments.optionalString("title").flatMap(TaskChangeTools.nonEmpty), title != event.title {
                change.title = title
                fields.append(ChangeField(label: "Title", before: event.title, after: title))
            }
            if let location = arguments.optionalString("location").flatMap(TaskChangeTools.nonEmpty) {
                let new = TaskChangeTools.isNone(location) ? "" : location
                change.location = new
                fields.append(ChangeField(label: "Location", before: event.subtitle, after: new.isEmpty ? "None" : new))
            }
            guard !fields.isEmpty else { return "Nothing to change on “\(event.title)”." }

            var proposal = ChangeProposal(
                kind: .updateEvent,
                headline: change.start != nil && change.title == nil ? L10n.tr("eventchangetools.move.event", "Move event") : nil,
                subject: subject(event, now: now, calendar: calendar, format: context.timeFormat()),
                fields: fields,
                offersAlwaysAllow: context.offersAlwaysAllow
            )
            if event.isRecurring { proposal.notes = [L10n.tr("eventchangetools.only.this.occurrence", "Only this occurrence.")] }
            let finalChange = change
            let finalFields = fields
            let moved = change.start != nil
            return await ChangeRunner.run(proposal, context: context) {
                let (before, after) = try await changes.updateEvent(reference, finalChange)
                let summary = finalFields.map { "\($0.label.lowercased()) \($0.reportValue)" }.joined(separator: ", ")
                return .init(
                    text: moved ? L10n.tr(
                        "eventchangetools.moved",
                        "Moved “\(String(describing: after.title))”"
                    ) : L10n.tr(
                        "eventchangetools.changed",
                        "Changed “\(String(describing: after.title))”"
                    ),
                    detail: finalFields.map { "\($0.displayLabel): \($0.displayValue($0.after) ?? "")" }.joined(separator: ", "),
                    undo: {
                        _ = try await changes.updateEvent(after.reference, EventChange(
                            title: before.title, start: before.start, end: before.end, location: before.location ?? ""
                        ))
                    },
                    report: "Done — “\(after.title)”: \(summary)."
                )
            }
        }
    }

    // MARK: - delete_event

    package static func delete(_ context: AssistantToolContext) -> AssistantTool {
        .answering(
            name: "delete_event",
            description: context.brief("Delete one event (one occurrence of a repeating one). The user approves it in the app.", "Delete an event."),
            parameters: context.parameters([
                .init(name: "event", kind: .string, description: context.brief(eventArgument, "The event's title."))
            ], optional: [
                .init(name: "when", kind: .string, description: whenArgument, isRequired: false)
            ])
        ) { arguments in
            guard let changes = context.changes else { return "Changes aren't available here." }
            let found = try await AssistantTargetResolver.event(try arguments.string("event"), when: arguments.optionalString("when"), context: context)
            guard case .found(let event) = found else { return TaskChangeTools.unresolved(found) }
            let reference: EventEditReference
            switch editable(event, forEditing: false) {
            case .success(let value): reference = value
            case .failure(let message): return message.text
            }
            let restorable = event.attendees.isEmpty && !event.isRecurring
            var proposal = ChangeProposal(kind: .deleteEvent, subject: subject(event, now: context.now(), calendar: context.calendar, format: context.timeFormat()))
            if let warning = EventEditability.of(event).deleteWarning { proposal.notes.append(warning) }
            if event.isRecurring { proposal.notes.append(L10n.tr("eventchangetools.only.this.occurrence", "Only this occurrence.")) }
            if !restorable { proposal.notes.append(L10n.tr("eventchangetools.this.can.t.be.undone", "This can't be undone.")) }
            return await ChangeRunner.run(proposal, context: context) {
                let removed = try await changes.deleteEvent(reference)
                var done = ChangeRunner.Performed(text: L10n.tr(
                    "eventchangetools.deleted",
                    "Deleted “\(String(describing: removed.title))”"
                ), report: "Done — “\(removed.title)” is deleted.")
                if restorable && removed.canRecreate {
                    let draft = removed.draft
                    done.undo = { _ = try await changes.createEvent(draft) }
                }
                return done
            }
        }
    }

    // MARK: -

    package struct Refusal: Error { let text: String }

    /// Whether the app may change it (`EventEditability`, the rules the
    /// event popover uses too) — told to the model as text if not.
    package static func editable(_ event: AgendaEventModel, forEditing: Bool) -> Result<EventEditReference, Refusal> {
        let editability = EventEditability.of(event)
        guard let reference = event.editReference, forEditing ? editability.canEdit : editability.canDelete else {
            let reason = editability.readOnlyReason(locale: Locale(identifier: "en")) ?? "it's in a calendar that can't be changed"
            return .failure(Refusal(text: "“\(event.title)” can't be \(forEditing ? "changed" : "deleted") from DayEdge: \(reason)"))
        }
        return .success(reference)
    }

    package static func subject(_ event: AgendaEventModel, now: Date, calendar: Calendar,
                                format: TimeFormat = .twentyFourHour) -> ChangeSubject {
        ChangeSubject.event(event, now: now, calendar: calendar, format: format)
    }

    /// The created event as a result line — with its reference, so the
    /// model can show it.
    package static func line(for snapshot: EventSnapshot, context: AssistantToolContext) async -> String? {
        let day = context.calendar.startOfDay(for: snapshot.start)
        let interval = DateInterval(start: day, end: context.calendar.date(byAdding: .day, value: 1, to: day) ?? day)
        let events = await context.data.agenda(in: interval, calendar: context.calendar).flatMap(\.events)
        guard let event = events.first(where: { $0.editReference?.eventIdentifier == snapshot.eventIdentifier }) else { return nil }
        return context.eventLine(event, day: day, showsDay: true)
    }
}
