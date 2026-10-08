import SwiftUI
import UI

/// The chat's input, in the toolbar row — the search field's mirror: the
/// same one-row geometry as the search palette as it opens (surface
/// insets, radius, optical offset) and its surface. Where the search
/// field has its magnifier, the composer has its send arrow (↓: answers
/// appear below) or Stop while an answer is being written (Esc too —
/// routed by the root view, see `ChatSession.escape()`), so the cursor
/// sits exactly where it does in search. Return sends, ⇧Return adds a
/// line.
package struct ChatComposerView: View {
    @Environment(\.themePalette) private var theme

    @Binding package var draft: String
    package let canSend: Bool
    /// An answer is being written: the send button becomes Stop.
    package var isResponding = false
    package var focus: FocusState<Bool>.Binding
    package let onSend: () -> Void
    package var onStop: () -> Void = {}

    @Environment(\.colorSchemeContrast) private var contrast

    package var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Chat.composerIconGap) {
            // The magnifier's own box (same glyph, same font), so the text
            // starts exactly where the search field's does; the control
            // is centred on it.
            Image(systemName: "magnifyingglass")
                .hidden()
                .overlay { sendButton }
            TextField("", text: $draft,
                      prompt: Text(L10n.tr("chatcomposerview.ask.about.your.schedule", "Ask about your schedule…")).foregroundStyle(theme.chat.composerPlaceholder),
                      axis: .vertical)
                .textFieldStyle(.plain)
                // The search field's type, so the text doesn't change shape
                // between them.
                .font(AppTheme.TextStyle.eventTitle)
                .foregroundStyle(theme.chat.composerText)
                .lineLimit(1...AppTheme.Chat.composerMaxLines)
                .focused(focus)
                .onKeyPress(.return, phases: .down) { press in
                    // ⇧Return: a new line (at the end — the composer is short).
                    if press.modifiers.contains(.shift) {
                        draft += "\n"
                    } else {
                        onSend()
                    }
                    return .handled
                }
                .padding(.vertical, 3)
        }
        // The search row's content inset, measured from the surface.
        .padding(.leading, AppTheme.horizontalPadding - SearchBarView.surfaceHorizontalInset)
        .padding(.trailing, 14)
        // Exactly where the search field's content is (the surface below
        // sits a little low, as the search palette's does), so switching
        // between them leaves the cursor where it was.
        .padding(.vertical, 10)
        .frame(minHeight: AppTheme.Chat.composerMinHeight)
        // The field's surface, shared with the search field.
        .background { PanelFieldSurface() }
        .contentShape(shape)
        .onTapGesture { focus.wrappedValue = true }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: PanelFieldSurface.cornerRadius, style: .continuous)
    }

    @ViewBuilder
    private var sendButton: some View {
        if isResponding { stopButton } else { sendArrow }
    }

    /// Neutral, not the accent: stopping isn't the primary action.
    private var stopButton: some View {
        Button(action: onStop) {
            Image(systemName: "stop.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(theme.chat.stopGlyph)
                .frame(width: AppTheme.Chat.sendDiameter, height: AppTheme.Chat.sendDiameter)
                .themedSurface(.floatingControl, fill: theme.chat.stopFill, in: Circle())
                .surfaceElevation(.floatingControl)
        }
        .buttonStyle(.plain)
        .help(L10n.tr("chatcomposerview.stop.generating.esc", "Stop generating (Esc)"))
        .accessibilityLabel(L10n.tr("chatcomposerview.stop.generating", "Stop generating"))
    }

    private var sendArrow: some View {
        Button(action: onSend) {
            Image(systemName: "arrow.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(canSend ? theme.chat.sendEnabledGlyph : theme.chat.sendDisabledGlyph)
                .frame(width: AppTheme.Chat.sendDiameter, height: AppTheme.Chat.sendDiameter)
                .themedSurface(.selectedFloatingControl,
                                 fill: canSend ? theme.chat.accent : theme.chat.sendDisabledFill, in: Circle())
                .surfaceElevation(.selectedFloatingControl)
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .animation(.easeOut(duration: 0.12), value: canSend)
        .accessibilityLabel(L10n.tr("chatcomposerview.send", "Send"))
    }
}
