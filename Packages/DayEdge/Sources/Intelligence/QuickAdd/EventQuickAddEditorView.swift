import SwiftUI
import Domain
import UI

/// Create Event, expanded in place — Quick Add's sibling: the same header,
/// grid, controls and keys (`QuickAddEditorView` describes them), with an
/// event's fields. When its time runs into a meeting, that meeting sits on
/// top — drawn by the caller as a search result row (no Join pill, so its
/// time never wraps) — under a note in the conflict's colour.
package struct EventQuickAddEditorView<OverlapRow: View>: View {
    @Environment(\.themePalette) var theme
    @Environment(\.timeFormat) var timeFormat
    @Environment(\.dateFormatter) var dateFormatter

    @Binding package var edit: EventQuickAddEdit
    package let calendars: [CalendarSource]
    package let overlap: EventOverlap?
    @ViewBuilder package let overlapRow: (AgendaEventModel) -> OverlapRow
    package var focus: FocusState<QuickAddField?>.Binding
    @Binding package var openEditor: QuickAddField?
    package let iconColumn: CGFloat
    package let iconToText: CGFloat

    var calendar: Calendar { .autoupdatingCurrent }

    package var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let overlap {
                overlapNote(overlap)
                    .padding(.bottom, QuickAddGrid.headerGap)
                    .transition(.opacity)
            }
            header
                .padding(.bottom, QuickAddGrid.headerGap)

            VStack(alignment: .leading, spacing: QuickAddGrid.rowSpacing) {
                row(L10n.tr("eventquickaddeditorview.calendar", "Calendar"), .calendar) {
                    choiceControl(.calendar, value: calendarTitle, options: calendarOptions, selection: edit.calendarID) {
                        edit.calendarID = $0
                    }
                }
                row(L10n.tr("eventquickaddeditorview.date", "Date"), .date) {
                    control(.date, value: dateText, placeholder: "", minWidth: QuickAddGrid.shortControlWidth) { datePopover }
                }
                row(L10n.tr("eventquickaddeditorview.starts", "Starts"), .time) {
                    control(.time, value: edit.isAllDay ? nil : timeFormat.time(edit.start),
                            placeholder: L10n.tr("eventquickaddeditorview.all.day", "All day"), minWidth: QuickAddGrid.shortControlWidth) { startPopover }
                }
                if !edit.isAllDay {
                    row(L10n.tr("eventquickaddeditorview.ends", "Ends"), .endTime) {
                        control(.endTime, value: endText, placeholder: "", minWidth: QuickAddGrid.shortControlWidth) { endPopover }
                    }
                }
                row(L10n.tr("eventquickaddeditorview.location", "Location"), .location) { locationField }
                row(L10n.tr("eventquickaddeditorview.repeat", "Repeat"), .recurrence) {
                    choiceControl(.recurrence, value: edit.recurrence.title,
                                  options: repeatOptions.map { ($0, $0.title) }, selection: edit.recurrence) { edit.recurrence = $0 }
                }
            }
        }
        .font(.system(size: 12))
        .animation(.easeOut(duration: 0.15), value: overlap)
        .onChange(of: openEditor) { previous, current in
            if current == nil, let previous { focus.wrappedValue = previous }
        }
    }

    // MARK: Overlap

    /// "Overlaps" in the conflict's colour, over the meeting itself.
    private func overlapNote(_ overlap: EventOverlap) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: iconToText) {
                Circle()
                    .fill(overlap.conflict == .busy ? theme.conflict.busy : theme.conflict.unconfirmed)
                    .frame(width: AppTheme.Conflict.dotSize, height: AppTheme.Conflict.dotSize)
                    .frame(width: iconColumn)
                Text(overlap.conflict == .busy ? L10n.tr(
                    "eventquickaddeditorview.overlaps", "Overlaps"
                ) : L10n.tr(
                    "eventquickaddeditorview.overlaps.not.accepted.yet", "Overlaps, not accepted yet"
                ))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(overlap.conflict == .busy ? theme.editor.overlapBusyText : theme.editor.overlapUnconfirmedText)
            }
            overlapRow(overlap.event)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.tr("eventquickaddeditorview.overlaps.f87ad2", "Overlaps \(String(describing: overlap.event.title))"))
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: iconToText) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 13))
                .foregroundStyle(calendarColor)
                .frame(width: iconColumn)
                .accessibilityHidden(true)
            TextField(L10n.tr("eventquickaddeditorview.title", "Title"), text: $edit.title)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.editor.titleText)
                .opacity(edit.title.isEmpty ? theme.editor.nativePlaceholderOpacity : 1)
                .focused(focus, equals: .title)
                .accessibilityLabel(L10n.tr("eventquickaddeditorview.title", "Title"))
        }
    }

    // MARK: Grid

    private func row<Control: View>(_ label: String, _ field: QuickAddField, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .foregroundStyle(theme.editor.labelText)
                .frame(width: QuickAddGrid.labelWidth, alignment: .leading)
                .accessibilityHidden(true)
            control()
            Spacer(minLength: 0)
        }
        .frame(height: QuickAddGrid.controlHeight)
        .padding(.leading, iconColumn + iconToText)
    }
}
