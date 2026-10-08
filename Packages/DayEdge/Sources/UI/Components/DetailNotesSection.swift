import Domain
import SwiftUI

/// The Notes section of a detail popover, edited in place: the text (or
/// "Add notes") until clicked, then an editor that grows with its text up
/// to a cap, scrolling with the app's thin scroller. Leaving it saves; Esc
/// cancels.
package struct DetailNotesSection: View {
    @Environment(\.themePalette) private var theme

    package let notes: String?
    package var isKeyboardSelected = false
    /// Bumped by the card's keyboard: start editing.
    package var editRequest = 0
    /// nil = the new notes; called only when they changed.
    package let onCommit: (String?) -> Void

    package static let maxHeight: CGFloat = 150

    @State private var isEditing = false
    @State private var draft = ""
    @State private var isHovering = false
    @State private var contentHeight: CGFloat = 0
    @FocusState private var isFocused: Bool

    package var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DetailSectionLabel(title: L10n.tr("detailnotessection.notes", "Notes"))
            if isEditing {
                scroller { editor }
            } else {
                Button {
                    draft = notes ?? ""
                    isEditing = true
                    DispatchQueue.main.async { isFocused = true }
                } label: {
                    scroller {
                        Text(notes ?? L10n.tr("detailnotessection.add.notes", "Add notes"))
                            .font(.system(size: 12))
                            .foregroundStyle(notes == nil
                                ? theme.secondaryText.opacity(isHovering ? 0.95 : 0.7)
                                : theme.secondaryText)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .detailRowHover(isHovering || isKeyboardSelected)
                }
                .buttonStyle(.plain)
                .onHover { isHovering = $0 }
                .onChange(of: editRequest) { _, _ in
                    draft = notes ?? ""
                    isEditing = true
                    DispatchQueue.main.async { isFocused = true }
                }
                .accessibilityLabel(notes == nil ? L10n.tr(
                    "detailnotessection.add.notes", "Add notes"
                ) : L10n.tr(
                    "detailnotessection.notes.1d31d8", "Notes: \(String(describing: notes ?? ""))"
                ))
            }
        }
        .onChange(of: isFocused) { wasFocused, focused in
            if wasFocused, !focused { commit() }
        }
        .onDisappear { commit() }
    }

    /// Grows with its text (its own scrolling off), so the surrounding
    /// scroller does the scrolling past the cap.
    private var editor: some View {
        ZStack(alignment: .topLeading) {
            // Invisible twin that gives the editor its natural height.
            Text(draft.isEmpty ? " " : draft + " ")
                .font(.system(size: 12))
                .padding(.horizontal, 5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hidden()
            TextEditor(text: $draft)
                .font(.system(size: 12))
                .foregroundStyle(theme.primaryText)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .scrollIndicators(.never)
                .focused($isFocused)
                .onExitCommand { isEditing = false }
                // ↩ is a new line; ⌘↩ finishes.
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    isFocused = false
                    return .handled
                }
        }
        .frame(minHeight: 36)
    }

    private func scroller<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ThemedScrollView {
            content()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .frame(height: min(max(contentHeight, 16), Self.maxHeight))
    }

    private func commit() {
        guard isEditing else { return }
        isEditing = false
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != (notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines) {
            onCommit(trimmed.isEmpty ? nil : draft)
        }
    }
}
