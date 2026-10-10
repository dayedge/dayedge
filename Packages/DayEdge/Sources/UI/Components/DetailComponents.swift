import SwiftUI

/// Shared pieces of the app's object-detail popovers (Event Details, Task
/// Details): surface, divider, and icon rows, so both read as siblings.
extension View {
    package func detailSurface() -> some View {
        modifier(DetailSurfaceModifier())
    }
}

package struct DetailDivider: View {
    @Environment(\.themePalette) private var theme

    package var body: some View {
        Divider()
            .overlay(theme.chrome.divider)
            .padding(.vertical, 8)
    }
}

/// The detail popovers' one row geometry — read-only and editable rows put
/// their icon and text at exactly the same x, never tweaked row by row. An
/// editable value sits on its own rounded inset surface (only the value,
/// not the icon), lit on hover and while its editor is open.
package enum DetailMetrics {
    package static let iconWidth: CGFloat = 14
    /// Icon column → the value's surface.
    package static let iconToValue: CGFloat = 4
    /// The value's surface, around its text.
    package static let valueInsetH: CGFloat = 6
    package static let valueInsetV: CGFloat = 3
    package static let valueRadius: CGFloat = 7
    package static let font = Font.system(size: 12)
    package static let iconFont = Font.system(size: 11)
    /// Between property rows (their surfaces carry their own inset).
    package static let rowSpacing: CGFloat = 2
    /// Identity block → the first property row.
    package static let identityToRows: CGFloat = 11
}

/// What an editable row shows: presentation-first when idle.
package enum DetailRowState: Equatable {
    case idle, hover, keyboardSelected, editing, disabled

    package func fill(theme: ThemePalette) -> Color {
        switch self {
        case .hover: return theme.detail.hoverFill
        case .keyboardSelected, .editing: return theme.detail.activeFill
        case .idle, .disabled: return .clear
        }
    }
}

/// The icon column every detail row shares.
package struct DetailRowIcon: View {
    @Environment(\.themePalette) private var theme

    package let symbol: String

    package var body: some View {
        Image(systemName: symbol)
            .font(DetailMetrics.iconFont)
            .foregroundStyle(theme.secondaryText)
            .frame(width: DetailMetrics.iconWidth)
            .padding(.top, DetailMetrics.valueInsetV + 1)
    }
}

extension View {
    /// The value's rounded inset surface (`state` lights it).
    package func detailValueSurface(_ state: DetailRowState) -> some View {
        modifier(DetailValueSurfaceModifier(state: state))
    }
}

package struct DetailRow: View {
    @Environment(\.themePalette) private var theme

    package let icon: String
    package let text: String
    package var tint: Color?
    package var strikethrough = false

    package var body: some View {
        HStack(alignment: .top, spacing: DetailMetrics.iconToValue) {
            DetailRowIcon(symbol: icon)
            Text(text)
                .font(DetailMetrics.font)
                .foregroundStyle(tint ?? theme.primaryText)
                .strikethrough(strikethrough)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .detailValueSurface(.idle)
        }
    }
}

/// Section label inside a detail popover ("Notes", "Attendees" style).
package struct DetailSectionLabel: View {
    @Environment(\.themePalette) private var theme

    package let title: String

    package var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.secondaryText)
    }
}

/// An editable property shown as plain metadata — the same icon column,
/// font and rhythm as `DetailRow` — that only reveals editability on
/// hover: a faint highlight and, where it applies, a small clear button.
/// Callers wrap it in the Button or Menu that opens the actual editor.
package struct DetailValueLabel: View {
    @Environment(\.themePalette) private var theme

    package let icon: String
    package let text: String
    package var isPlaceholder = false
    package var tint: Color?
    package var isHovering = false
    /// Its editor is open.
    package var isEditing = false
    /// The card's keyboard selection (↑ / ↓).
    package var isKeyboardSelected = false
    package var onClear: (() -> Void)?

    private var state: DetailRowState {
        if isEditing { return .editing }
        if isKeyboardSelected { return .keyboardSelected }
        return isHovering ? .hover : .idle
    }

    package var body: some View {
        HStack(alignment: .top, spacing: DetailMetrics.iconToValue) {
            DetailRowIcon(symbol: icon)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(text)
                    .font(DetailMetrics.font)
                    .foregroundStyle(isPlaceholder
                        ? theme.secondaryText.opacity(isHovering ? 0.95 : 0.7)
                        : (tint ?? theme.primaryText))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isHovering, let onClear {
                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill")
                            .font(DetailMetrics.iconFont)
                            .foregroundStyle(theme.content.detailMetadata)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.tr("detailcomponents.remove", "Remove"))
                }
            }
            .detailValueSurface(state)
        }
        .contentShape(Rectangle())
    }
}

extension View {
    /// The quiet hover lift shared by editable detail rows: a soft rounded
    /// fill that extends a few points past the row, never a border.
    package func detailRowHover(_ isHovering: Bool) -> some View {
        modifier(DetailRowHoverModifier(isHovering: isHovering))
    }
}

/// A metadata row whose editor opens on click (a popover or inline field):
/// `DetailValueLabel` in a plain button, with its own hover.
package struct DetailEditorRow: View {
    package let icon: String
    package let text: String
    package var isPlaceholder = false
    package var tint: Color?
    /// Its editor is open (the value stays lit).
    package var isEditing = false
    package var isKeyboardSelected = false
    package var onClear: (() -> Void)?
    package let action: () -> Void

    @State private var isHovering = false

    package var body: some View {
        Button(action: action) {
            DetailValueLabel(icon: icon, text: text, isPlaceholder: isPlaceholder, tint: tint,
                             isHovering: isHovering, isEditing: isEditing,
                             isKeyboardSelected: isKeyboardSelected, onClear: onClear)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// A one-line text property edited in place (location, URL): metadata
/// until clicked, then a plain field. Return or leaving the field saves,
/// Esc cancels; an emptied field removes the value (`onCommit("")`).
package struct DetailInlineTextRow: View {
    @Environment(\.themePalette) private var theme

    package let icon: String
    package let value: String?
    package let placeholder: String
    package var prompt = ""
    package var display: (String) -> String = { $0 }
    package var isKeyboardSelected = false
    /// Bumped by the card's keyboard (↩ on this row): start editing.
    package var editRequest = 0
    /// Tab (true) / ⇧Tab (false) — after saving, the card moves on.
    package var onTab: ((Bool) -> Void)?
    /// The trimmed text; "" removes it. Called only when it changed.
    package let onCommit: (String) -> Void

    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    package var body: some View {
        if isEditing {
            HStack(alignment: .top, spacing: DetailMetrics.iconToValue) {
                DetailRowIcon(symbol: icon)
                TextField(prompt, text: $draft)
                    .textFieldStyle(.plain)
                    .font(DetailMetrics.font)
                    .foregroundStyle(theme.primaryText)
                    .focused($isFocused)
                    .onSubmit { isFocused = false }
                    .onExitCommand {
                        isEditing = false // cancel: nothing saved
                    }
                    .onKeyPress(.tab, phases: .down) { press in
                        guard let onTab else { return .ignored }
                        isFocused = false
                        onTab(!press.modifiers.contains(.shift))
                        return .handled
                    }
                    .detailValueSurface(.editing)
            }
            .onChange(of: isFocused) { wasFocused, focused in
                if wasFocused, !focused { commit() }
            }
            .onDisappear { commit() }
        } else {
            DetailEditorRow(
                icon: icon,
                text: value.map(display) ?? placeholder,
                isPlaceholder: value == nil,
                isKeyboardSelected: isKeyboardSelected,
                onClear: value == nil ? nil : { onCommit("") }
            ) { startEditing() }
            .onChange(of: editRequest) { _, _ in startEditing() }
        }
    }

    private func startEditing() {
        draft = value ?? ""
        isEditing = true
        DispatchQueue.main.async { isFocused = true }
    }

    private func commit() {
        guard isEditing else { return }
        isEditing = false
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != (value ?? "") { onCommit(trimmed) }
    }
}

/// A metadata row whose editor is a native menu of choices (Repeat, Alert,
/// Priority): plain metadata until hovered, with an optional clear button
/// outside the menu's hit area.
package struct DetailMenuRow<Items: View>: View {
    @Environment(\.themePalette) private var theme

    package let icon: String
    package let text: String
    package var isPlaceholder = false
    package var onClear: (() -> Void)?
    @ViewBuilder package let items: () -> Items

    @State private var isHovering = false

    package var body: some View {
        Menu {
            items()
        } label: {
            DetailValueLabel(icon: icon, text: text, isPlaceholder: isPlaceholder, isHovering: isHovering)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .overlay(alignment: .trailing) {
            if isHovering, let onClear {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.content.detailMetadata)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("detailcomponents.remove", "Remove"))
            }
        }
        .onHover { isHovering = $0 }
    }
}

/// A menu item with a checkmark when it's the current choice.
package struct DetailCheckButton: View {
    package let title: String
    package let isOn: Bool
    package let action: () -> Void

    package var body: some View {
        Button(action: action) {
            if isOn { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }
}

private struct DetailSurfaceModifier: ViewModifier {
    @Environment(\.themePalette) private var theme
    func body(content: Content) -> some View {
        content.padding(14).frame(width: 390)
            .themedSurface(.elevated, fill: theme.workingSurface ?? theme.background, in: Rectangle())
    }
}

private struct DetailValueSurfaceModifier: ViewModifier {
    @Environment(\.themePalette) private var theme
    let state: DetailRowState
    func body(content: Content) -> some View {
        content.padding(.horizontal, DetailMetrics.valueInsetH)
            .padding(.vertical, DetailMetrics.valueInsetV)
            .background(RoundedRectangle(cornerRadius: DetailMetrics.valueRadius, style: .continuous)
                .fill(state.fill(theme: theme)))
            .contentShape(Rectangle())
    }
}

private struct DetailRowHoverModifier: ViewModifier {
    @Environment(\.themePalette) private var theme
    let isHovering: Bool
    func body(content: Content) -> some View {
        content.padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(theme.detail.hoverFill.opacity(isHovering ? 1 : 0))
                .padding(.horizontal, -6))
            .contentShape(Rectangle())
    }
}
