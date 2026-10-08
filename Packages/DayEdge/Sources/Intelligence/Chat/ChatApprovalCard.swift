import SwiftUI
import UI

/// A change the app wants to make, waiting for the user: what (drawn the
/// way the app draws it), what changes, and the decision. Allow is a native
/// split button whose menu offers "Always Allow …" (remote models, never for
/// deletions); a deletion's primary button is a red Delete.
///
/// Keys: ⌘↩ allows (plain ↩ is the composer's "send"), Esc declines (routed
/// by the root view — `ChatSession.escape()`), ⌘⌫ deletes, but only while
/// the composer is empty, where it can't mean "delete text". Always Allow
/// has no key: a lasting permission takes a deliberate click.
package struct ChatApprovalCard: View {
    @Environment(\.themePalette) private var theme

    package let proposal: ChangeProposal
    package var allowsDeleteShortcut = true
    package let onDecide: (ApprovalDecision) -> Void

    private typealias Chat = AppTheme.Chat

    package var body: some View {
        DecisionCardSurface(title: proposal.title, symbol: proposal.kind.symbol, isDestructive: proposal.kind.isDestructive) {
            DecisionSubjectRow(subject: proposal.subject, isStruckThrough: proposal.kind.isDestructive)

            if !proposal.fields.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(proposal.fields.enumerated()), id: \.offset) { _, field in
                        FieldRow(field: field)
                    }
                }
            }

            ForEach(proposal.notes, id: \.self) { note in
                Text(verbatim: note)
                    .font(Chat.cardNoteFont)
                    .foregroundStyle(theme.secondaryText)
            }
        } actions: {
            Button { onDecide(.deny) } label: { DecisionKeyedLabel(title: L10n.tr("chatapprovalcard.don.t.allow", "Don’t Allow"), key: "esc") }
                .buttonStyle(.bordered)
            primary
        }
        .padding(.horizontal, AppTheme.horizontalPadding)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(proposal.title): \(proposal.subject.title)")
    }

    @ViewBuilder
    private var primary: some View {
        if proposal.kind.isDestructive {
            Button(role: .destructive) { onDecide(.allow) } label: {
                DecisionKeyedLabel(title: L10n.tr("chatapprovalcard.delete", "Delete"), key: allowsDeleteShortcut ? "⌘⌫" : nil)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.chat.destructive)
            .keyboardShortcut(allowsDeleteShortcut ? KeyboardShortcut(.delete, modifiers: .command) : nil)
        } else if proposal.offersAlwaysAllow {
            // The native split button: Allow, and its menu.
            Menu {
                Button(proposal.kind.alwaysAllowTitle) { onDecide(.alwaysAllow) }
            } label: {
                DecisionKeyedLabel(title: L10n.tr("chatapprovalcard.allow", "Allow"), key: "⌘↩")
            } primaryAction: {
                onDecide(.allow)
            }
            .menuStyle(.button)
            .buttonStyle(.borderedProminent)
            .tint(theme.chat.accent)
            .fixedSize()
            // A menu's primary action takes no shortcut; an invisible button does.
            .background(
                Button("") { onDecide(.allow) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .opacity(0)
                    .accessibilityHidden(true)
            )
        } else {
            Button { onDecide(.allow) } label: { DecisionKeyedLabel(title: L10n.tr("chatapprovalcard.allow", "Allow"), key: "⌘↩") }
                .buttonStyle(.borderedProminent)
                .tint(theme.chat.accent)
                .keyboardShortcut(.return, modifiers: .command)
        }
    }
}

/// "Time   ~~Today 10:30–11:00~~ → Today 15:00–15:30".
private struct FieldRow: View {
    @Environment(\.themePalette) private var theme

    let field: ChangeField

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: field.displayLabel)
                .foregroundStyle(theme.secondaryText)
                .frame(width: AppTheme.Chat.cardFieldLabelWidth, alignment: .leading)
            if let before = field.displayValue(field.before), !before.isEmpty {
                Text(verbatim: before)
                    .strikethrough(color: theme.secondaryText)
                    .foregroundStyle(theme.secondaryText)
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }
            Text(verbatim: field.displayValue(field.after) ?? "")
                .foregroundStyle(theme.primaryText)
        }
        .font(AppTheme.Chat.cardDetailFont)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// What became of a change: "✓ Created “Faktura” · Tomorrow 15:00  Undo".
package struct ChatChangeReceiptView: View {
    @Environment(\.themePalette) private var theme

    package let receipt: ChatChangeReceipt
    package let onUndo: () -> Void

    private typealias Chat = AppTheme.Chat

    package var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(symbolColor)
            Text(verbatim: line)
                .foregroundStyle(receipt.state == .done ? theme.primaryText.opacity(0.85) : theme.chat.receiptMuted)
                .strikethrough(receipt.state == .undone, color: theme.chat.receiptMuted)
                .lineLimit(2)
            Spacer(minLength: 4)
            if receipt.canUndo {
                Button(L10n.tr("chatapprovalcard.undo", "Undo"), action: onUndo)
                    .buttonStyle(.link)
                    .foregroundStyle(theme.chat.accent)
            } else if receipt.state == .undone {
                Text(L10n.tr("chatapprovalcard.undone", "Undone")).foregroundStyle(theme.chat.receiptMuted)
            }
        }
        .font(Chat.receiptFont)
        .padding(.horizontal, AppTheme.horizontalPadding)
        .accessibilityElement(children: .combine)
    }

    private var line: String {
        switch receipt.state {
        case .failed(let message): return "\(receipt.text) — \(message)"
        default: return [receipt.text, receipt.detail].compactMap { $0 }.joined(separator: " · ")
        }
    }

    private var symbol: String {
        switch receipt.state {
        case .done: return "checkmark.circle.fill"
        case .declined: return "xmark.circle"
        case .failed: return "exclamationmark.triangle"
        case .undone: return "arrow.uturn.backward.circle"
        }
    }

    private var symbolColor: Color {
        switch receipt.state {
        case .done: return theme.chat.receiptDone
        case .failed: return theme.accentRed
        case .declined, .undone: return theme.chat.receiptMuted
        }
    }
}
