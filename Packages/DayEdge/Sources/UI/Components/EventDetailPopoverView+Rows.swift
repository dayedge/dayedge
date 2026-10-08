import AppKit
import SwiftUI
import Domain

extension EventDetailPopoverView {
    // MARK: Repeat and alert

    /// Calendar's Repeat choices, read from the event's own date; Custom…
    /// morphs the editor. A new rule changes this and future events.
    var repeatRow: some View {
        DetailEditorRow(icon: "repeat", text: event.recurrence == .never ? L10n.tr("eventdetailpopoverview.rows.add.repeat", "Add repeat") : event.recurrence.title,
                        isPlaceholder: event.recurrence == .never,
                        isEditing: editor == "repeat", isKeyboardSelected: selectedRow == "repeat",
                        onClear: event.recurrence == .never ? nil : { setRepeat(nil) }) { open("repeat") }
            .propertyEditor(isPresented: editorBinding("repeat")) {
                RepeatEditor(current: event.recurrenceRule, anchor: event.startDate ?? date) { rule in
                    editor = nil
                    setRepeat(rule)
                }
            }
    }

    private func setRepeat(_ rule: TaskRecurrenceRule?) {
        guard rule != event.recurrenceRule else { return }
        let change = rule.map { EventChange(recurrenceRule: $0) } ?? EventChange(recurrence: .never)
        actions?.edit(event, change, span: event.isRecurring ? .futureEvents : .thisEvent)
    }

    /// "15 minutes before", "+1" when there are more.
    var alertText: String {
        guard let first = event.alerts.first else { return L10n.tr("eventdetailpopoverview.rows.add.alert", "Add alert") }
        let title = first.title(isAllDay: event.isAllDay, format: timeFormat)
        return event.alerts.count > 1 ? "\(title) +\(event.alerts.count - 1)" : title
    }

    /// The first alert: None, Calendar's presets, or a specific time (which
    /// morphs the editor); any other alerts stay.
    var alertRow: some View {
        let current = event.alerts.first
        let presets = EventAlert.presets(isAllDay: event.isAllDay)
        var items = [ChoiceItem(id: "none", title: L10n.tr("eventdetailpopoverview.rows.none", "None"), isChecked: current == nil), .separator("after-none")]
        items += presets.enumerated().map { index, alert in
            ChoiceItem(id: "p\(index)", title: alert.title(isAllDay: event.isAllDay, format: timeFormat), isChecked: alert == current)
        }
        if let current, !presets.contains(current) {
            items += [.separator("before-current"), ChoiceItem(id: "current", title: current.title(isAllDay: event.isAllDay, format: timeFormat), isChecked: true)]
        }
        let specificStart: Date = {
            if case .at(let date)? = current { return date }
            return (event.startDate ?? date).addingTimeInterval(-15 * 60)
        }()
        return DetailEditorRow(icon: "bell", text: alertText, isPlaceholder: current == nil,
                               isEditing: editor == "alert", isKeyboardSelected: selectedRow == "alert",
                               onClear: current == nil ? nil : { setFirstAlert(nil) }) { open("alert") }
            .propertyEditor(isPresented: editorBinding("alert")) {
                AlertEditor(items: items, specificStart: specificStart, onChoose: { item in
                    editor = nil
                    switch item.id {
                    case "none": setFirstAlert(nil)
                    case "current": break
                    default:
                        if let index = Int(item.id.dropFirst()), presets.indices.contains(index) { setFirstAlert(presets[index]) }
                    }
                }, onSpecific: { date in
                    editor = nil
                    setFirstAlert(.at(date))
                })
            }
    }

    private func setFirstAlert(_ alert: EventAlert?) {
        let rest = Array(event.alerts.dropFirst())
        let alerts = alert.map { [$0] + rest } ?? rest
        guard alerts != event.alerts else { return }
        apply(EventChange(alerts: alerts))
    }

    /// A new day, the same time of day and length.
    func moveTo(day: Date) {
        // The picker can report one click twice: only the first, while the
        // editor is still open, moves the event.
        guard editor == "date" else { return }
        editor = nil
        guard let start = event.startDate else { return }
        let calendar = Calendar.autoupdatingCurrent
        let time = calendar.dateComponents([.hour, .minute], from: start)
        let newStart = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day) ?? day
        guard !calendar.isDate(newStart, equalTo: start, toGranularity: .minute) else { return }
        apply(EventChange(start: newStart))
    }

    func commitTitle() {
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            titleDraft = event.title // an empty title isn't allowed: revert
        } else if trimmed != event.title {
            apply(EventChange(title: trimmed))
        }
    }

    /// A repeating event asks which events first, on the docked card.
    func apply(_ change: EventChange) {
        actions?.editAskingSpan(event, change)
    }

    var invitedBy: String? {
        guard case .invitation(let organizer?) = editability else { return nil }
        return L10n.tr("eventdetailpopoverview.rows.invited.by", "Invited by \(String(describing: organizer))")
    }

    func detailRow(icon: String, text: String) -> some View {
        DetailRow(icon: icon, text: text, strikethrough: isCancelled)
    }

    var attendeesSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(L10n.tr("eventdetailpopoverview.rows.attendees", "Attendees · \(String(describing: event.attendees.count))"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.primaryText.opacity(0.72))
                if isHoveringAttendeesHeader {
                    CopyIconButton(value: allAttendeesCopyValue, helpText: L10n.tr("eventdetailpopoverview.rows.copy.all.emails", "Copy all emails"))
                }
                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
            .onHover { isHoveringAttendeesHeader = $0 }

            ThemedScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(event.attendees) { attendee in
                        AttendeeRow(attendee: attendee, statusGlyph: statusGlyph(attendee.status))
                    }
                }
                .padding(.vertical, 2)
            }
            // Compact: caps out at ~4 rows before scrolling instead of
            // always reserving space for the full list.
            .frame(height: min(CGFloat(event.attendees.count) * 19 + 4, 92))
        }
    }

    /// Every attendee's email — falling back to their name when EventKit
    /// couldn't give one (see `EventAttendee.email`'s doc comment) so
    /// nobody silently drops out of the pasted list — joined the way a
    /// mail client's To/Cc field expects to receive multiple addresses.
    private var allAttendeesCopyValue: String {
        event.attendees.map { $0.email ?? $0.name }.joined(separator: "; ")
    }

    /// A lightweight disclosure row keeps notes collapsed by default;
    /// expanding reveals a bounded scroll area using the shared scroller.
    func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                isNotesExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text(L10n.tr("eventdetailpopoverview.rows.notes", "Notes"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                    Spacer(minLength: 4)
                    Image(systemName: isNotesExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($focusedAction, equals: .notes)
            .help(isNotesExpanded ? L10n.tr("eventdetailpopoverview.rows.collapse.notes", "Collapse notes") : L10n.tr("eventdetailpopoverview.rows.expand.notes", "Expand notes"))

            if isNotesExpanded {
                ThemedScrollView {
                    Text(notes)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                }
                .frame(height: 140)
            }
        }
    }

    func myStatusRow(_ status: EventAttendee.Status) -> some View {
        let (symbol, color) = statusGlyph(status)
        return HStack(spacing: 6) {
            Text(L10n.tr("eventdetailpopoverview.rows.my.status", "My Status"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
            Spacer(minLength: 4)
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(color)
            Text(Self.statusLabel(status))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.primaryText)
        }
    }

    /// Shared between the attendee list (via `AttendeeRow`, computed once
    /// per row here rather than inside that view) and the "My Status" row,
    /// so both always agree on what each status looks like.
    private func statusGlyph(_ status: EventAttendee.Status) -> (symbol: String, color: Color) {
        switch status {
        case .accepted: return ("checkmark.circle.fill", theme.acceptedStatus)
        case .declined: return ("xmark.circle.fill", theme.declinedStatus)
        case .tentative: return ("questionmark.circle.fill", theme.tentativeStatus)
        case .pending, .unknown: return ("circle", theme.secondaryText)
        }
    }

    private static func statusLabel(_ status: EventAttendee.Status) -> String {
        switch status {
        case .accepted: return L10n.tr("eventdetailpopoverview.rows.accepted", "Accepted")
        case .declined: return L10n.tr("eventdetailpopoverview.rows.declined", "Declined")
        case .tentative: return L10n.tr("eventdetailpopoverview.rows.tentative", "Tentative")
        case .pending: return L10n.tr("eventdetailpopoverview.rows.not.responded", "Not Responded")
        case .unknown: return L10n.tr("eventdetailpopoverview.rows.unknown", "Unknown")
        }
    }

    package init(
        event: AgendaEventModel,
        date: Date,
        actionRequest: EventDetailActionRequest? = nil,
        onActionFocusChange: @escaping (EventDetailFocusableAction?) -> Void = { _ in }
    ) {
        self.event = event
        self.date = date
        self.actionRequest = actionRequest
        self.onActionFocusChange = onActionFocusChange
    }
}
