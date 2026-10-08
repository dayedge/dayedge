import SwiftUI
import Domain
import UI

extension SearchBarView {
    /// The same selected surface, grown into Quick Add.
    /// `current` is the edit as of this render: creating clears the model's
    /// edit while SwiftUI may still read the binding as the editor leaves
    /// (and animates out), so it falls back to that instead of trapping.
    func quickAddEditor(_ current: QuickAddEdit) -> some View {
        QuickAddEditorView(
            edit: Binding(get: { palette.edit ?? current }, set: { newValue in
                // Only while Quick Add is really open — never resurrect it.
                if palette.edit != nil { palette.edit = newValue }
            }),
            lists: palette.taskLists(),
            focus: $quickAddFocus,
            openEditor: Binding(get: { palette.openChildEditor }, set: { palette.openChildEditor = $0 }),
            iconColumn: Self.iconColumn,
            iconToText: Self.iconToText
        )
        // Saving: the draft stops being editable and quietly settles.
        .disabled(palette.isCommitting)
        .opacity(palette.isCommitting ? 0.7 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.09), value: palette.isCommitting)
        .padding(.horizontal, Self.rowInsetH)
        .padding(.vertical, Self.rowInsetV)
        .background(
            ThemedSurface(role: .nested, fill: theme.editor.panelFill,
                            shape: RoundedRectangle(cornerRadius: Self.suggestionRowCornerRadius, style: .continuous))
        )
    }

    /// Create Event grown in place: the same surface, the event's fields.
    func eventEditor(_ current: EventQuickAddEdit) -> some View {
        EventQuickAddEditorView(
            edit: Binding(get: { palette.eventEdit ?? current }, set: { newValue in
                if palette.eventEdit != nil { palette.eventEdit = newValue }
            }),
            calendars: palette.eventCalendarOptions,
            overlap: palette.editOverlap,
            overlapRow: { event in overlapRow(event) },
            focus: $quickAddFocus,
            openEditor: Binding(get: { palette.openChildEditor }, set: { palette.openChildEditor = $0 }),
            iconColumn: Self.iconColumn,
            iconToText: Self.iconToText
        )
        .disabled(palette.isCommitting)
        .opacity(palette.isCommitting ? 0.7 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.09), value: palette.isCommitting)
        .padding(.horizontal, Self.rowInsetH)
        .padding(.vertical, Self.rowInsetV)
        .background(
            ThemedSurface(role: .nested, fill: theme.editor.panelFill,
                            shape: RoundedRectangle(cornerRadius: Self.suggestionRowCornerRadius, style: .continuous))
        )
    }
}
