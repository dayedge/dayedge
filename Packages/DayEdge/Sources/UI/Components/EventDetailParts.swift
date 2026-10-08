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
/// Done (↩) saves, Cancel (Esc) doesn't. Moving the start keeps the length.
struct EventTimeEditor: View {
    let start: Date
    let end: Date
    let isAllDay: Bool
    let onCommit: (EventChange) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftStart = Date()
    @State private var draftEnd = Date()
    @State private var draftAllDay = false

    private var calendar: Calendar { .autoupdatingCurrent }

    var body: some View {
        PropertyEditor(width: .compact, onCancel: { dismiss() }, onDone: {
            commit()
            dismiss()
        }, content: {
            Toggle(L10n.tr("eventdetailparts.all.day", "All-day"), isOn: Binding(get: { draftAllDay }, set: setAllDay))
                .toggleStyle(.checkbox)
            if !draftAllDay {
                PropertyEditorField(label: "Starts") {
                    DatePicker(L10n.tr("eventdetailparts.starts", "Starts"), selection: Binding(get: { draftStart }, set: moveStart), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                PropertyEditorField(label: "Ends") {
                    DatePicker(L10n.tr("eventdetailparts.ends", "Ends"), selection: $draftEnd, in: draftStart.addingTimeInterval(5 * 60)..., displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
            }
        })
        .datePickerStyle(.field)
        .onAppear {
            draftStart = start
            draftEnd = end
            draftAllDay = isAllDay
        }
    }

    private func moveStart(_ new: Date) {
        let length = draftEnd.timeIntervalSince(draftStart)
        draftStart = new
        draftEnd = new.addingTimeInterval(length)
    }

    /// All-day spans whole days; back to timed, an hour at 9:00.
    private func setAllDay(_ allDay: Bool) {
        draftAllDay = allDay
        let day = calendar.startOfDay(for: draftStart)
        if allDay {
            draftStart = day
            draftEnd = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        } else {
            draftStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
            draftEnd = draftStart.addingTimeInterval(3600)
        }
    }

    /// Only what actually changed is saved.
    private func commit() {
        if draftAllDay != isAllDay {
            onCommit(EventChange(start: draftStart, end: draftEnd, isAllDay: draftAllDay))
        } else if draftStart != start || draftEnd != end {
            onCommit(EventChange(start: draftStart, end: draftEnd))
        }
    }
}
