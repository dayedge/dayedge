import AppKit
import SwiftUI
import Domain

/// The event detail card, shown when tapping an agenda row,
/// with a compact, scrollable attendee list reusing `ThemedScrollView`.
///
/// The user's own events without attendees are edited in place, like Task
/// Details (title, day, time and all-day, location, notes) — through
/// `EventActionCoordinator`, with `EventEditability` deciding. Meetings
/// with people and invitations read as before, marked only by a small lock
/// (its tooltip says why: EventKit can't change
/// invitees, responses or notify anyone) on the calendar chip. Open in
/// Calendar and Delete live
/// in the right-click menu, as in Calendar — no footer.
/// A change to a repeating event asks which events, on the panel's docked
/// `DecisionCard` (`EventActionCoordinator.editAskingSpan`) — no popover of
/// its own.
package struct EventDetailPopoverView: View {
    @Environment(\.themePalette) var theme

    package let event: AgendaEventModel
    package let date: Date
    package var actionRequest: EventDetailActionRequest?
    package var onActionFocusChange: (EventDetailFocusableAction?) -> Void = { _ in }

    @Environment(\.eventActionCoordinator) var actions
    @State var titleDraft = ""
    @FocusState var isTitleFocused: Bool
    @Environment(\.dismiss) var dismiss
    @Environment(\.openAppSettings) private var openSettings
    @Environment(\.timeFormat) var timeFormat
    @Environment(\.dateFormatter) var dateFormatter
    /// The one property editor open ("date", "time", "repeat", "alert").
    @State var editor: String?
    /// The keyboard's row (↑ / ↓); editors return to it when they close.
    @State var selectedRow: String?
    @State var locationRequest = 0
    @State var notesRequest = 0
    /// Calendars it may move to (own events), for the identity's selector.
    @State private var calendarOptions: [CollectionOption] = []

    var editability: EventEditability { actions?.editability(of: event) ?? .readOnly }
    var canEdit: Bool { editability.canEdit }

    @State var isNotesExpanded = false
    @FocusState var focusedAction: EventDetailFocusableAction?
    @FocusState private var isContainerFocused: Bool

    var isCancelled: Bool { event.status == .cancelled }

    /// Reuses the same "start – end" formatting the Agenda row uses (the
    /// endpoint gains date context for a multi-day event — "15:45 –
    /// Tomorrow 16:45" — rather than the popover showing a plain
    /// same-looking range regardless of which day it actually ends). Falls
    /// back to the plain display strings for data with no real dates
    /// (mock/legacy).
    var timeText: String? {
        if let label = AgendaTimeMetadataLabel.build(event: event, day: date, calendar: .autoupdatingCurrent,
                                                     format: timeFormat) {
            return label.displayText
        }
        return event.rangeText(timeFormat)
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Group {
                if canEdit {
                    VStack(alignment: .leading, spacing: DetailMetrics.rowSpacing) { editableRows }
                } else {
                    VStack(alignment: .leading, spacing: DetailMetrics.rowSpacing) {
                        detailRow(icon: "calendar", text: dateFormatter.format(date, .standard))

                        if let timeText {
                            detailRow(icon: AppTheme.Symbol.time, text: timeText)
                        }

                        if event.recurrence != .never {
                            detailRow(icon: "repeat", text: event.recurrence.title)
                        }

                        // Alerts are the user's own, even on someone else's event.
                        if editability.canEditAlerts {
                            alertRow
                        } else if !event.alerts.isEmpty {
                            detailRow(icon: "bell", text: alertText)
                        }

                        if let subtitle = event.subtitle {
                            detailRow(icon: "location", text: subtitle)
                        }
                    }
                }
            }
            .padding(.top, DetailMetrics.identityToRows)

            if let meetingLink = event.meetingLink {
                JoinCallButton(
                    link: meetingLink,
                    actionFocus: $focusedAction,
                    actionRequest: actionRequest
                )
                .padding(.top, 8)
            }

            if !event.attendees.isEmpty {
                sectionDivider
                attendeesSection
            }

            if canEdit {
                sectionDivider
                DetailNotesSection(notes: event.notes, isKeyboardSelected: selectedRow == "notes",
                                   editRequest: notesRequest) { apply(EventChange(notes: $0 ?? "")) }
            } else if let notes = event.notes, !notes.isEmpty {
                sectionDivider
                notesSection(notes)
            }

            if let myResponseStatus = event.myResponseStatus {
                sectionDivider
                myStatusRow(myResponseStatus)
            }
        }
        .onAppear { titleDraft = event.title }
        .task(id: canEdit) {
            calendarOptions = canEdit ? await actions?.calendarOptions() ?? [] : []
        }
        .onChange(of: event.title) { _, title in if !isTitleFocused { titleDraft = title } }
        .onChange(of: isTitleFocused) { wasFocused, focused in if wasFocused, !focused { commitTitle() } }
        .detailKeyboard(handleKey)

        .detailSurface()
        .focusable()
        .focused($isContainerFocused)
        .focusEffectDisabled()
        .onAppear {
            focusedAction = nil
            isContainerFocused = true
        }
        .onDisappear { onActionFocusChange(nil) }
        .onChange(of: focusedAction) { _, action in
            onActionFocusChange(action)
        }
        .onChange(of: actionRequest) { _, request in
            guard request?.eventID == event.id else { return }
            if request?.action == .toggleNotes {
                isNotesExpanded.toggle()
            }
        }
    }

    private var sectionDivider: some View { DetailDivider() }

    /// The object's identity: its marker, title (editable on own events)
    /// and calendar — a selector that's part of the identity, not a row.
    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(event.color)
                .frame(width: 10, height: 10)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 1) {
                if canEdit {
                    // A plain field reads as the title itself until focused.
                    TextField(L10n.tr("eventdetailpopoverview.title", "Title"), text: $titleDraft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1...4)
                        .focused($isTitleFocused)
                        .onSubmit { isTitleFocused = false }
                        .onExitCommand {
                            titleDraft = event.title
                            isTitleFocused = false
                        }
                        .onKeyPress(.tab, phases: .down) { press in
                            isTitleFocused = false
                            step(from: "title", forward: !press.modifiers.contains(.shift))
                            return .handled
                        }
                } else {
                    Text(verbatim: event.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .strikethrough(isCancelled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let invitedBy {
                    Text(invitedBy)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !event.calendarName.isEmpty {
                CollectionSelector(
                    current: CollectionOption(id: event.editReference?.calendarIdentifier ?? "",
                                              title: event.calendarName, color: event.color),
                    options: calendarOptions,
                    lockHelp: editability.readOnlyReason == nil ? nil : L10n.tr(
                        "eventdetailpopoverview.read.only.in.dayedge.0b0fb3", "Read-only in DayEdge — respond or edit in Apple Calendar"
                    ),
                    manageTitle: L10n.tr("eventdetailpopoverview.manage.calendars", "Manage Calendars…"),
                    onManage: openSettings.map { open in { open(.calendars) } }
                ) { id in apply(EventChange(calendarIdentifier: id)) }
                .padding(.top, 1)
            }
        }
    }

    @State var isHoveringAttendeesHeader = false
}
