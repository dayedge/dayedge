import SwiftUI
import UI

/// One transcript row, drawn with the conversation's own pieces. Compared
/// by value, so rows that didn't change are never redrawn while an answer
/// streams or the composer is typed in.
package struct ChatTranscriptRowView: View, Equatable {
    @Environment(\.themePalette) private var theme

    package let row: ChatTranscriptRow
    package let objects: ChatObjectContext
    package let approvals: ChatApprovals
    /// Only the latest reply's approval card uses it.
    package let isComposerEmpty: Bool

    /// `objects` (closures, fixed for a session) and `approvals` (observed
    /// directly) are left out: their changes reach the rows reading them.
    package static func == (a: ChatTranscriptRowView, b: ChatTranscriptRowView) -> Bool {
        a.row == b.row && a.isComposerEmpty == b.isComposerEmpty
    }

    package var body: some View {
        content
            .padding(.top, row.topGap)
    }

    @ViewBuilder
    private var content: some View {
        switch row.kind {
        case .user(let text):
            HStack {
                Spacer(minLength: 0)
                Text(text)
                    .font(AppTheme.Chat.messageFont)
                    .foregroundStyle(theme.chat.userBubbleText)
                    .textSelection(.enabled)
                    .padding(.horizontal, AppTheme.Chat.userBubblePaddingH)
                    .padding(.vertical, AppTheme.Chat.userBubblePaddingV)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Chat.userBubbleRadius, style: .continuous)
                            .fill(theme.chat.userBubbleFill)
                    )
                    .frame(maxWidth: AppTheme.Chat.userBubbleMaxWidth, alignment: .trailing)
            }
            .padding(.horizontal, AppTheme.horizontalPadding)
        case .receipt(let receipt):
            ChatChangeReceiptView(receipt: receipt) {
                Task { await approvals.undo(receipt) }
            }
        case .pending(let isLatest):
            Group {
                if isLatest, let proposal = approvals.pending {
                    ChatApprovalCard(proposal: proposal, allowsDeleteShortcut: isComposerEmpty) { approvals.decide($0) }
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                } else {
                    ChatThinkingView()
                        .padding(.horizontal, AppTheme.horizontalPadding)
                }
            }
            .animation(.easeOut(duration: 0.16), value: approvals.pending?.id)
        case .prose(let text):
            Text(ChatProse.attributed(text))
                .font(AppTheme.Chat.assistantFont)
                .foregroundStyle(theme.chat.assistantText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, AppTheme.horizontalPadding)
        case .dayHeader(let day):
            // A miniature agenda: the day's calendar card on the rows'
            // content column, its events and tasks below.
            ChatDayTileHeader(reference: day, calendar: objects.calendar, onOpen: objects.showDay)
                .padding(.leading, AppTheme.AgendaRow.contentLeadingX)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .object(let part):
            ChatObjectReferenceRow(part: part, objects: objects)
        case .dates(let days):
            // Days on their own, aligned with the prose.
            ChatDatesView(days: days, calendar: objects.calendar, onOpen: objects.showDay)
                .padding(.leading, AppTheme.horizontalPadding - AppTheme.Chat.dateInset)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// "Thinking…" — a slow, low-amplitude breathing of the text;
/// still under Reduce Motion.
package struct ChatThinkingView: View {
    @Environment(\.themePalette) private var theme

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDimmed = false

    package var body: some View {
        Text(L10n.tr("chattranscriptrowview.thinking", "Thinking…"))
            .font(AppTheme.Chat.assistantFont)
            .foregroundStyle(theme.secondaryText)
            .opacity(isDimmed ? 0.55 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { isDimmed = true }
            }
    }
}
