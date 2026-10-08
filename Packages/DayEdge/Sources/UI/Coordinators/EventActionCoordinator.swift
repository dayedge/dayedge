import AppKit
import Foundation
import Domain

/// Where the app's event actions actually happen: opening URLs, copying,
/// editing and deleting. One instance is constructed at the app root and
/// read by every event view through the environment (see
/// `EventActionEnvironment.swift`).
///
/// Reversible actions just happen, with Undo in a `TransientNotice`. Only
/// what needs the user's input asks — a repeating event's scope, or a
/// deletion that can't be put back — through the panel's docked
/// `DecisionCard` (`DecisionCenter`), never a separate window.
@MainActor
package final class EventActionCoordinator {
    private let appleCalendar: AppleCalendarOpening
    private let removalService: CalendarEventRemoving
    private let occurrenceFinder: RecurringOccurrenceFinding
    private let noticeCenter: NoticeCenter
    private let reminderSuppression: ReminderSuppressionStore
    private let onNavigateOccurrence: @MainActor (OccurrenceNavigationTarget) async -> Void
    /// Editing and deleting events (the popover, the menu). nil: read-only.
    private let editor: CalendarEventEditing?
    private var occurrenceTask: Task<Void, Never>?
    private var occurrenceRequestID: UUID?
    private let decisions: DecisionCenter
    /// Occurrences being saved right now. A second request for one (a date
    /// picker reporting a click twice, a gesture ending twice) would look
    /// the event up at its old time — already moved — and fail.
    private var saving: Set<EventEditReference> = []

    package init(
        appleCalendar: AppleCalendarOpening,
        removalService: CalendarEventRemoving,
        occurrenceFinder: RecurringOccurrenceFinding,
        noticeCenter: NoticeCenter,
        reminderSuppression: ReminderSuppressionStore,
        editor: CalendarEventEditing? = nil,
        decisions: DecisionCenter? = nil,
        onNavigateOccurrence: @escaping @MainActor (OccurrenceNavigationTarget) async -> Void
    ) {
        self.editor = editor
        self.decisions = decisions ?? .shared
        self.appleCalendar = appleCalendar
        self.removalService = removalService
        self.occurrenceFinder = occurrenceFinder
        self.noticeCenter = noticeCenter
        self.reminderSuppression = reminderSuppression
        self.onNavigateOccurrence = onNavigateOccurrence
    }

    /// What an event menu item does — the menu and the panel's shortcuts
    /// both run it, so a key never does something its item doesn't.
    /// (Show in Calendar is search's own, `\.searchResultReveal`.)
    package func perform(_ action: EventContextMenuAction, for event: AgendaEventModel) { // swiftlint:disable:this cyclomatic_complexity - one case per menu action
        switch action {
        case .joinVideoCall: joinVideoCall(for: event)
        case .copyMeetingLink: copyMeetingLink(for: event)
        case .openLocationInMaps(let location): openLocationInMaps(location)
        case .openInAppleCalendar: openInAppleCalendar(for: event)
        case .nextOccurrence: goToOccurrence(from: event, direction: .next)
        case .previousOccurrence: goToOccurrence(from: event, direction: .previous)
        case .muteReminders: muteReminders(for: event)
        case .restoreReminders: restoreReminders(for: event)
        case .removeFromCalendar: requestRemoval(for: event)
        case .deleteEvent: requestDeletion(of: event)
        case .showInCalendar, .divider: break
        }
    }

    /// The items `event`'s menu offers right now.
    package func menuActions(for event: AgendaEventModel, inSearch: Bool = false) -> [EventContextMenuAction] {
        EventContextMenuPlan.actions(for: event, remindersMuted: areRemindersMuted(for: event),
                                     editability: editability(of: event), inSearch: inSearch)
    }

    package func joinVideoCall(for event: AgendaEventModel) {
        guard let link = event.meetingLink, let url = link.preferredURL ?? link.webURL else {
            noticeCenter.show(.information(title: L10n.tr("eventactioncoordinator.no.meeting.link.available", "No meeting link available")))
            return
        }
        if !NSWorkspace.shared.open(url) {
            noticeCenter.show(.error(title: L10n.tr("eventactioncoordinator.couldn.t.open.meeting.link", "Couldn’t open meeting link")))
        }
    }

    package func copyMeetingLink(for event: AgendaEventModel) {
        guard let url = event.meetingLink?.webURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
    }

    package func areRemindersMuted(for event: AgendaEventModel) -> Bool {
        reminderSuppression.isMuted(event)
    }

    package func muteReminders(for event: AgendaEventModel) {
        guard reminderSuppression.setMuted(true, for: event) else { return }
        noticeCenter.show(.success(
            title: L10n.tr("eventactioncoordinator.reminders.muted", "Reminders muted"),
            action: NoticeAction(title: L10n.tr("eventactioncoordinator.undo", "Undo"), handler: { [weak self] in
                self?.restoreReminders(for: event)
            })
        ))
    }

    package func restoreReminders(for event: AgendaEventModel) {
        guard reminderSuppression.setMuted(false, for: event) else { return }
        noticeCenter.show(.success(title: L10n.tr("eventactioncoordinator.reminders.restored", "Reminders restored")))
    }

    package func openLocationInMaps(_ location: String) {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: location)]
        guard let url = components?.url else { return }
        NSWorkspace.shared.open(url)
    }

    /// `nil` `calendarItemIdentifier` only happens for data with no real
    /// backing `EKEvent` (mock/legacy) — nothing to open, so this is a
    /// silent no-op there, same as every other action here already is for
    /// data it can't act on. No fallback if the deep link itself fails —
    /// see `AppleCalendarBridge`.
    package func openInAppleCalendar(for event: AgendaEventModel) {
        guard let identifier = event.calendarItemIdentifier else { return }
        let occurrence = event.occurrenceDate ?? event.startDate ?? Date()
        appleCalendar.openWithDetails(calendarItemIdentifier: identifier, occurrenceDate: occurrence)
    }

    package func goToOccurrence(from event: AgendaEventModel, direction: OccurrenceDirection) {
        guard let reference = event.recurrenceReference else { return }
        occurrenceTask?.cancel()
        let requestID = UUID()
        occurrenceRequestID = requestID
        let finder = occurrenceFinder
        occurrenceTask = Task { [weak self] in
            let target = await finder.adjacent(to: reference, direction: direction)
            guard !Task.isCancelled, let self, self.occurrenceRequestID == requestID else { return }
            if let target {
                await self.onNavigateOccurrence(target)
                guard !Task.isCancelled, self.occurrenceRequestID == requestID else { return }
                self.occurrenceTask = nil
                self.occurrenceRequestID = nil
            } else {
                self.occurrenceTask = nil
                self.occurrenceRequestID = nil
                self.noticeCenter.show(.information(
                    title: direction == .next
                        ? L10n.tr(
                            "eventactioncoordinator.no.next.occurrence.found",
                            "No next occurrence found"
                        ) : L10n.tr(
                            "eventactioncoordinator.no.previous.occurrence.found",
                            "No previous occurrence found"
                        )
                ))
            }
        }
    }

    /// A cancelled event's removal can't be undone, so it asks — on the
    /// docked card. Gated upstream by `EventContextMenuPlan` on
    /// `removalReference != nil`; this guard is the last line of defense.
    package func requestRemoval(for event: AgendaEventModel) {
        guard event.removalReference != nil else { return }
        let scope: CalendarRemovalScope = event.isRecurring ? .occurrence : .event
        decisions.present(DecisionRequest(
            kind: .destructive, title: scope.title, message: scope.message, subject: subject(event),
            actions: [
                DecisionAction(title: L10n.tr("eventactioncoordinator.cancel", "Cancel"), role: .cancel) {},
                DecisionAction(title: L10n.tr("eventactioncoordinator.remove", "Remove"), role: .destructive) { [weak self] in self?.removeCancelledEvent(event) }
            ]
        ))
    }

    /// EventKit commits this deletion to the source calendar. There is no
    /// reliable Undo, so `requestRemoval` asks first.
    package func removeCancelledEvent(_ event: AgendaEventModel) {
        guard let reference = event.removalReference else { return }
        do {
            try removalService.removeCancelledOccurrence(reference)
            noticeCenter.show(.success(title: event.isRecurring ? L10n.tr(
                "eventactioncoordinator.occurrence.removed",
                "Occurrence removed"
            ) : L10n.tr(
                "eventactioncoordinator.event.removed",
                "Event removed"
            )))
        } catch {
            noticeCenter.show(.error(title: L10n.tr("eventactioncoordinator.couldn.t.remove.event", "Couldn’t remove event"), message: Self.message(for: error)))
        }
    }

}

extension EventActionCoordinator {
    // MARK: - Editing (EventEditability decides what's allowed)

    /// The calendars an event may move to, for the Calendar selector.
    package func calendarOptions() async -> [CollectionOption] {
        await writableCalendars().map {
            CollectionOption(id: $0.identifier, title: $0.title, color: $0.color, group: $0.group)
        }
    }

    package func writableCalendars() async -> [WritableCalendar] { await editor?.writableCalendars() ?? [] }

    package func editability(of event: AgendaEventModel) -> EventEditability {
        editor == nil ? .readOnly : EventEditability.of(event)
    }

    /// Saves a change from the popover. One occurrence can be undone; a
    /// change to all future events can't (Calendar's own rule).
    /// The task's value: whether it was saved.
    @discardableResult
    package func edit(_ event: AgendaEventModel, _ change: EventChange, span: EventSpan = .thisEvent) -> Task<Bool, Never>? {
        let editability = editability(of: event)
        guard let editor, let reference = event.editReference,
              editability.canEdit || (change.isAlertsOnly && editability.canEditAlerts),
              !saving.contains(reference) else { return nil }
        saving.insert(reference)
        return Task { [weak self] in
            defer { self?.saving.remove(reference) }
            do {
                let (before, after) = try await editor.update(reference, change, span: span)
                guard let self else { return true }
                // A new repeat rule reshapes the series: no Undo (Calendar's rule too).
                let undo: NoticeAction? = span == .thisEvent && change.recurrence == nil && change.recurrenceRule == nil
                    ? NoticeAction(title: L10n.tr("eventactioncoordinator.undo", "Undo")) { [weak self] in self?.restore(before, from: after) }
                    : nil
                self.noticeCenter.show(.success(title: Self.title(for: change, before: before, after: after), action: undo))
                return true
            } catch {
                Self.refreshIfStale(error)
                self?.noticeCenter.show(.error(title: L10n.tr("eventactioncoordinator.couldn.t.change.event", "Couldn’t change event"), message: WriteFailureText.message(error)))
                return false
            }
        }
    }

    private func restore(_ before: EventSnapshot, from after: EventSnapshot) {
        guard let editor else { return }
        Task {
            let alertsOnly = before.title == after.title && before.start == after.start && before.end == after.end
                && before.isAllDay == after.isAllDay && before.location == after.location && before.notes == after.notes
            // Alerts alone come back alone — that also works on invitations.
            let change = alertsOnly && before.calendarIdentifier == after.calendarIdentifier
                ? EventChange(alerts: before.alerts)
                : EventChange(title: before.title, start: before.start, end: before.end, isAllDay: before.isAllDay,
                              location: before.location ?? "", notes: before.notes ?? "", alerts: before.alerts,
                              calendarIdentifier: before.calendarIdentifier)
            _ = try? await editor.update(after.reference, change)
        }
    }

    /// "Event moved to Fri 2 Oct 15:00–16:00" (same length), "Event now
    /// Today 10:00–11:15" (resized), "Alert changed", "Event updated".
    private static func title(for change: EventChange, before: EventSnapshot, after: EventSnapshot) -> String {
        if change.isAlertsOnly { return L10n.tr("eventactioncoordinator.alert.changed", "Alert changed") }
        if change.calendarIdentifier != nil, change.start == nil { return L10n.tr("eventactioncoordinator.moved.to", "Moved to \(String(describing: after.calendarTitle))") }
        if change.recurrence != nil || change.recurrenceRule != nil { return L10n.tr("eventactioncoordinator.repeat.changed", "Repeat changed") }
        guard change.start != nil || change.end != nil || change.isAllDay != nil else { return L10n.tr("eventactioncoordinator.event.updated", "Event updated") }
        let when = ChangeText.span(start: after.start, end: after.end, isAllDay: after.isAllDay,
                                     now: Date(), calendar: .autoupdatingCurrent, format: .current)
        let sameLength = after.end.timeIntervalSince(after.start) == before.end.timeIntervalSince(before.start)
        return sameLength ? L10n.tr(
            "eventactioncoordinator.event.moved.to",
            "Event moved to \(String(describing: when))"
        ) : L10n.tr(
            "eventactioncoordinator.event.now",
            "Event now \(String(describing: when))"
        )
    }

    // MARK: - Asking (only when needed)

    /// A change that may need a repeating event's scope first. `onFinish`
    /// says whether it was saved — false if cancelled or failed — so a drag
    /// preview stays where it was dropped while asking and saving, and goes
    /// back only when nothing changed.
    package func editAskingSpan(_ event: AgendaEventModel, _ change: EventChange, onFinish: ((Bool) -> Void)? = nil) {
        let save: (EventSpan) -> Void = { [weak self] span in
            let saving = self?.edit(event, change, span: span)
            Task { @MainActor in onFinish?(await saving?.value ?? false) }
        }
        guard event.isRecurring else { return save(.thisEvent) }
        decisions.present(.eventSpan(message: L10n.tr("eventactioncoordinator.apply.this.change.to", "Apply this change to:"), subject: subject(event), isDeleting: false) { span in
            if let span { save(span) } else { onFinish?(false) }
        })
    }

    /// Whether deleting asks first (the menu's "…").
    package func deletionAsks(_ event: AgendaEventModel) -> Bool {
        event.isRecurring || editability(of: event) != .editable
    }

    /// Delete. The user's own single event just goes, with Undo. What can't
    /// be put back asks on the docked card: a repeating event (which
    /// events?), and a meeting or invitation (nobody will be told).
    package func requestDeletion(of event: AgendaEventModel) {
        let editability = editability(of: event)
        guard editability.canDelete else { return }
        if event.isRecurring {
            let message = [editability.deleteWarning, L10n.tr("eventactioncoordinator.delete", "Delete:")].compactMap { $0 }.joined(separator: " ")
            decisions.present(.eventSpan(message: message, subject: subject(event), isDeleting: true) { [weak self] span in
                if let span { self?.delete(event, span: span) }
            })
        } else if editability == .editable {
            delete(event)
        } else {
            decisions.present(DecisionRequest(
                kind: .destructive, title: L10n.tr("eventactioncoordinator.delete.3d7bb0", "Delete “\(String(describing: event.title))”?"), message: editability.deleteWarning,
                subject: subject(event),
                actions: [
                    DecisionAction(title: L10n.tr("eventactioncoordinator.cancel", "Cancel"), role: .cancel) {},
                    DecisionAction(title: L10n.tr("eventactioncoordinator.delete.f6fdbe", "Delete"), role: .destructive) { [weak self] in self?.delete(event) }
                ]
            ))
        }
    }

    /// The event wasn't where the list said: the list is stale — refresh it
    /// so the next click doesn't hit the same ghost.
    private static func refreshIfStale(_ error: Error) {
        if case EventEditError.notFound? = error as? EventEditError { CalendarWriteScope.announce() }
    }

    private func subject(_ event: AgendaEventModel) -> ChangeSubject {
        ChangeSubject.event(event, now: Date(), calendar: .autoupdatingCurrent)
    }

    @discardableResult
    package func delete(_ event: AgendaEventModel, span: EventSpan = .thisEvent) -> Task<Void, Never>? {
        guard let editor, editability(of: event).canDelete, let reference = event.editReference else { return nil }
        return Task { [weak self] in
            do {
                let removed = try await editor.delete(reference, span: span)
                let undo: NoticeAction? = span == .thisEvent && removed.canRecreate
                    ? NoticeAction(title: L10n.tr("eventactioncoordinator.undo", "Undo")) { Task { _ = try? await editor.create(removed.draft) } }
                    : nil
                self?.noticeCenter.show(.success(title: L10n.tr("eventactioncoordinator.event.deleted", "Event deleted"), action: undo))
            } catch {
                Self.refreshIfStale(error)
                self?.noticeCenter.show(.error(title: L10n.tr("eventactioncoordinator.couldn.t.delete.event", "Couldn’t delete event"), message: WriteFailureText.message(error)))
            }
        }
    }

    private static func message(for error: Error) -> String {
        switch error as? EventRemovalError {
        case .occurrenceNotFound: L10n.tr(
            "eventactioncoordinator.this.event.could.no.longer.9f6ac9", "This event could no longer be found — it may have already changed or been removed."
        )
        case .noLongerCancelled: L10n.tr(
            "eventactioncoordinator.this.event.is.no.longer.554fba", "This event is no longer cancelled, so it wasn’t removed."
        )
        case .calendarNotWritable: L10n.tr("eventactioncoordinator.this.calendar.can.no.longer.be.modified", "This calendar can no longer be modified.")
        case nil: error.localizedDescription
        }
    }
}

// MARK: - Creating

extension EventActionCoordinator {
    /// A new event from the palette, with Undo. Throws (having told the
    /// user) when it can't be saved.
    package func create(_ draft: EventDraft) async throws -> EventSnapshot {
        guard let editor else { throw EventEditError.notWritable }
        do {
            let created = try await editor.create(draft)
            noticeCenter.show(.success(title: L10n.tr(
                "eventactioncoordinator.event.added",
                "Event added"
            ), action: NoticeAction(title: L10n.tr(
                "eventactioncoordinator.undo",
                "Undo"
            )) { [weak self] in
                Task { await self?.undoCreate(created) }
            }))
            return created
        } catch {
            noticeCenter.show(.error(title: L10n.tr("eventactioncoordinator.couldn.t.add.event", "Couldn’t add event"), message: WriteFailureText.message(error)))
            throw error
        }
    }

    /// The palette's Undo: the whole series for a repeating event; a failure
    /// is said, not swallowed.
    private func undoCreate(_ created: EventSnapshot) async {
        guard let editor else { return }
        do {
            try await editor.undoCreate(created)
        } catch {
            noticeCenter.show(.error(title: L10n.tr("eventactioncoordinator.couldn.t.undo", "Couldn’t undo"), message: WriteFailureText.message(error)))
        }
    }
}
