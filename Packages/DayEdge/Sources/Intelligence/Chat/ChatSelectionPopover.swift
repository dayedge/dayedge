import SwiftUI
import UI

/// The chats behind the Ask footer's pill, in the footer selectors'
/// grammar (`SelectorPopoverParts`): a passive title, every conversation —
/// the current one checked, then the earlier ones, newest first — and the
/// New Chat command below. Choosing one continues it.
///
/// Keyboard: ↑ ↓ move through chats and the command, Return or Space opens
/// (or runs it), ⌘N starts a new chat, Esc closes.
package struct ChatSelectionPopover: View {
    @Environment(\.themePalette) private var theme

    package let history: ChatHistory
    package let onNewChat: () -> Void
    package let onReopen: (ChatSession) -> Void

    @Environment(\.dismiss) private var dismiss
    /// A chat's index, or `sessions.count` for New Chat.
    @State private var focusedIndex: Int?
    @FocusState private var isFocused: Bool

    /// The current conversation first (when anything was asked in it).
    private var sessions: [ChatSession] {
        let current = history.current.flatMap { $0.isEmpty ? nil : $0 }
        return (current.map { [$0] } ?? []) + history.past
    }

    package var body: some View {
        let sessions = sessions
        VStack(alignment: .leading, spacing: 0) {
            SelectorPopoverHeader(title: L10n.tr("chatselectionpopover.chats", "Chats"))
            if sessions.isEmpty {
                SelectorPopoverEmptyText(text: L10n.tr("chatselectionpopover.no.chats.yet", "No chats yet"))
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(sessions.enumerated()), id: \.element.startedAt) { index, session in
                        ChatSelectionRow(session: session, isCurrent: session === history.current,
                                         isFocused: focusedIndex == index) { open(session) }
                            .onHover { if $0 { focusedIndex = index } }
                    }
                }
            }
            SelectorPopoverSeparator()
            SelectorCommandRow(symbol: "plus", title: L10n.tr("chatselectionpopover.new.chat", "New Chat"), isFocused: focusedIndex == sessions.count,
                               action: startNew)
                .onHover { if $0 { focusedIndex = sessions.count } }
                .help(L10n.tr("chatselectionpopover.new.chat.n", "New Chat (⌘N)"))
        }
        .padding(SelectorPopoverMetrics.padding)
        .frame(width: 260, alignment: .leading)
        .selectorPopoverSurface(theme)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear { isFocused = true }
        .onKeyPress(.downArrow) { moveFocus(1, stops: sessions.count + 1); return .handled }
        .onKeyPress(.upArrow) { moveFocus(-1, stops: sessions.count + 1); return .handled }
        .onKeyPress(.return) { activate(sessions); return .handled }
        .onKeyPress(.space) { activate(sessions); return .handled }
        .onKeyPress("n", phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            startNew()
            return .handled
        }
        .onKeyPress(.escape) { dismiss(); return .handled }
    }

    private func activate(_ sessions: [ChatSession]) {
        guard let focusedIndex else { return }
        if sessions.indices.contains(focusedIndex) {
            open(sessions[focusedIndex])
        } else if focusedIndex == sessions.count {
            startNew()
        }
    }

    private func startNew() {
        dismiss()
        onNewChat()
    }

    private func open(_ session: ChatSession) {
        dismiss()
        if session !== history.current { onReopen(session) }
    }

    private func moveFocus(_ delta: Int, stops: Int) {
        let index = focusedIndex ?? (delta > 0 ? -1 : stops)
        focusedIndex = min(max(index + delta, 0), stops - 1)
    }

    package init(history: ChatHistory, onNewChat: @escaping () -> Void, onReopen: @escaping (ChatSession) -> Void) {
        self.history = history
        self.onNewChat = onNewChat
        self.onReopen = onReopen
    }
}

/// One conversation: a check for the current one, its title and when it
/// started.
private struct ChatSelectionRow: View {
    @Environment(\.themePalette) private var theme

    let session: ChatSession
    let isCurrent: Bool
    let isFocused: Bool
    let action: () -> Void

    var body: some View {
        let style = SelectorRowStyle(theme: theme, isHighlighted: isFocused)
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: SelectorPopoverMetrics.iconToText) {
                // A menu's checkmark: in the text's color, like
                // `ChoiceListEditor`'s.
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(style.primary)
                    .frame(width: SelectorPopoverMetrics.iconColumn)
                    .opacity(isCurrent ? 1 : 0)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.title ?? L10n.tr("chatselectionpopover.chat", "Chat"))
                        .font(DetailMetrics.font)
                        .foregroundStyle(style.primary)
                        .lineLimit(1)
                    Text(session.startedAt.formatted(.relative(presentation: .named)))
                        .font(.system(size: 11))
                        .foregroundStyle(style.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, SelectorPopoverMetrics.rowPaddingV)
            .padding(.horizontal, SelectorPopoverMetrics.rowPaddingH)
            .background(SelectorRowBackground(isFocused: isFocused))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
