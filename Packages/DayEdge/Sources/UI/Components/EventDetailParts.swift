import Domain
import SwiftUI

/// One row in the attendee list. A separate view (rather than inline in
/// the `ForEach`) so each row can own its own hover state — the copy icon
/// only appears for the row currently under the mouse, not all of them.
struct AttendeeRow: View {
    @Environment(\.themePalette) private var theme

    let attendee: EventAttendee
    let statusGlyph: (symbol: String, color: Color)

    @State private var isHovering = false

    /// What tapping the row's copy icon puts on the clipboard — the
    /// email when EventKit could give one, the display name otherwise.
    private var copyValue: String { attendee.email ?? attendee.name }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: statusGlyph.symbol)
                .font(.system(size: 10))
                .foregroundStyle(statusGlyph.color.opacity(0.82))
            Text(attendee.name)
                .font(.system(size: 11))
                .foregroundStyle(theme.primaryText.opacity(0.78))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            if isHovering {
                CopyIconButton(
                    value: copyValue,
                    helpText: attendee.email != nil ? L10n.tr("eventdetailparts.copy.email", "Copy email") : L10n.tr("eventdetailparts.copy.name", "Copy name")
                )
            }
            Spacer(minLength: 4)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

/// A small hover-revealed copy affordance, shared by the attendees
/// section's "copy all" header action and each `AttendeeRow`. Briefly
/// swaps to a checkmark as its own feedback that the copy actually
/// happened, since there's nothing else on screen that would show it.
struct CopyIconButton: View {
    @Environment(\.themePalette) private var theme

    let value: String
    var helpText: String = L10n.tr("eventdetailparts.copy", "Copy")

    @State private var didCopy = false

    var body: some View {
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(value, forType: .string)
            didCopy = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { didCopy = false }
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10))
                .foregroundStyle(didCopy ? theme.controlAccent : theme.secondaryText)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(didCopy ? L10n.tr("eventdetailparts.copied", "Copied") : helpText)
    }
}

/// An event's time, edited as a draft — every saved change can move the
/// event (and close the card), so nothing is written while adjusting.
/// Done (↩) saves, Cancel (Esc) doesn't. Starts and Ends each hold a date and
/// a time, so an event can run over several days; `EventTiming` keeps the end
/// after the start and the length when the start moves.
struct EventTimeEditor: View {
    let onCommit: (EventChange) -> Void

    @Environment(\.dismiss) private var dismiss
    /// The time as it was, to save only what changed.
    private let original: EventTiming
    @State private var timing: EventTiming

    init(start: Date, end: Date, isAllDay: Bool, onCommit: @escaping (EventChange) -> Void) {
        let timing = EventTiming(start: start, end: end, isAllDay: isAllDay, calendar: .autoupdatingCurrent)
        self.onCommit = onCommit
        original = timing
        _timing = State(initialValue: timing)
    }

    var body: some View {
        PropertyEditor(width: .standard, onCancel: { dismiss() }, onDone: {
            commit()
            dismiss()
        }, content: {
            Toggle(L10n.tr("eventdetailparts.all.day", "All-day"), isOn: $timing.isAllDay)
                .toggleStyle(.checkbox)
            let starts = L10n.tr("eventdetailparts.starts", "Starts")
            let ends = L10n.tr("eventdetailparts.ends", "Ends")
            PropertyEditorField(label: starts) { moment(starts, day: $timing.firstDay, time: $timing.start) }
            PropertyEditorField(label: ends) { moment(ends, day: $timing.lastDay, time: $timing.end) }
        })
        .datePickerStyle(.field)
    }

    /// A date and, unless all day, a time beside it.
    private func moment(_ label: String, day: Binding<Date>, time: Binding<Date>) -> some View {
        HStack(spacing: 6) {
            DatePicker(label, selection: day, displayedComponents: .date)
                .labelsHidden()
            if !timing.isAllDay {
                DatePicker(label, selection: time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
        }
    }

    /// Only what actually changed is saved.
    private func commit() {
        if timing.isAllDay != original.isAllDay {
            onCommit(EventChange(start: timing.start, end: timing.end, isAllDay: timing.isAllDay))
        } else if timing != original {
            onCommit(EventChange(start: timing.start, end: timing.end))
        }
    }
}
