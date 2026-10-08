import SwiftUI
import Domain

/// The app's one decision language — the Ask approval card's surface,
/// type, subject row and buttons, shared by every decision: inline in a
/// conversation (`ChatApprovalCard`) or docked at the panel's bottom
/// (`DecisionCard` via `DecisionDock`). Colors: `ThemePalette.chat`; geometry: `AppTheme.Chat`.
/// In a conversation (a card among messages), or docked at the panel's
/// bottom (the toast's sibling — its surface, edges and type).
package enum DecisionPlacement { case inline, docked }

package struct DecisionCardSurface<Content: View, Actions: View>: View {
    @Environment(\.themePalette) private var theme

    package let title: String
    package var symbol: String?
    package var isDestructive = false
    package var placement: DecisionPlacement = .inline
    @ViewBuilder package let content: () -> Content
    @ViewBuilder package let actions: () -> Actions

    package init(title: String, symbol: String? = nil, isDestructive: Bool = false, placement: DecisionPlacement = .inline,
                 @ViewBuilder content: @escaping () -> Content, @ViewBuilder actions: @escaping () -> Actions) {
        self.title = title
        self.symbol = symbol
        self.isDestructive = isDestructive
        self.placement = placement
        self.content = content
        self.actions = actions
    }

    private typealias Chat = AppTheme.Chat

    package var body: some View {
        let docked = placement == .docked
        let stack = VStack(alignment: .leading, spacing: docked ? 8 : Chat.cardSpacing) {
            Group {
                if let symbol {
                    Label(title, systemImage: symbol)
                } else {
                    Text(title)
                }
            }
            .font(docked ? AppTheme.TextStyle.eventTitle : Chat.cardHeadlineFont)
            .foregroundStyle(isDestructive ? theme.chat.destructive : (docked ? theme.primaryText : theme.chat.cardHeadline))
            .accessibilityAddTraits(.isHeader)

            content()

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                actions()
            }
            .controlSize(.regular)
            .padding(.top, docked ? 2 : 0)
        }
        if docked {
            stack
                .padding(.horizontal, BottomSurface.contentPaddingH)
                .padding(.vertical, 14)
                .bottomSurface()
        } else {
            stack
                .padding(Chat.cardPadding)
                .themedSurface(.nested, fill: theme.chat.cardFill, in: RoundedRectangle(cornerRadius: Chat.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Chat.cardRadius, style: .continuous).strokeBorder(theme.chat.cardStroke, lineWidth: 0.5))
        }
    }
}

/// The object a decision is about: its marker (a task's ring, an event's
/// dot), title and one detail line.
package struct DecisionSubjectRow: View {
    @Environment(\.themePalette) private var theme

    package let subject: ChangeSubject
    package var isStruckThrough = false

    private typealias Chat = AppTheme.Chat

    package var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            marker
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: subject.title)
                    .font(Chat.cardTitleFont)
                    .foregroundStyle(theme.primaryText)
                    .strikethrough(isStruckThrough, color: theme.secondaryText)
                    .lineLimit(2)
                if let detail = subject.detail {
                    Text(detail)
                        .font(Chat.cardDetailFont)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var marker: some View {
        switch subject.marker {
        case .ring(let color):
            Circle().strokeBorder(color, lineWidth: 1.5).frame(width: 13, height: 13)
        case .dot(let color):
            Circle().fill(color).frame(width: 10, height: 10).padding(1.5)
        }
    }

    package init(subject: ChangeSubject, isStruckThrough: Bool = false) {
        self.subject = subject
        self.isStruckThrough = isStruckThrough
    }
}

/// A button title with its key, quieter: "Allow  ⌘↩".
package struct DecisionKeyedLabel: View {
    package let title: String
    package let key: String?

    package var body: some View {
        HStack(spacing: 6) {
            Text(title)
            if let key {
                Text(key)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .opacity(0.6)
                    .accessibilityHidden(true)
            }
        }
    }

    package init(title: String, key: String?) {
        self.title = title
        self.key = key
    }
}

/// Any `DecisionRequest`, on the shared surface. Buttons by meaning: Cancel
/// and other choices plain, the safe default prominent, destructive ones red.
/// The keyboard's selection (← / →) wears the focus ring and the ↩ hint.
package struct DecisionCard: View {
    @Environment(\.themePalette) private var theme

    package let request: DecisionRequest
    package let selectedID: DecisionAction.ID?
    /// Show the selection's focus ring (after ← / →).
    package var showsSelectionRing = false
    package var placement: DecisionPlacement = .docked
    package let onChoose: (DecisionAction) -> Void

    package var body: some View {
        DecisionCardSurface(title: request.title, symbol: request.symbol,
                            isDestructive: request.kind == .destructive && request.symbol == nil,
                            placement: placement) {
            if let message = request.message {
                Text(message)
                    .font(placement == .docked ? AppTheme.TextStyle.eventSubtitle : AppTheme.Chat.cardDetailFont)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let subject = request.subject {
                DecisionSubjectRow(subject: subject)
            }
        } actions: {
            ForEach(request.actions) { action in
                button(for: action)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel([request.title, request.message].compactMap { $0 }.joined(separator: ". "))
    }

    @ViewBuilder
    private func button(for action: DecisionAction) -> some View {
        let isSelected = action.id == selectedID
        let key: String? = action.role == .cancel ? "esc" : (isSelected ? "↩" : nil)
        let label = DecisionKeyedLabel(title: action.title, key: key)
        if action.alternatives.isEmpty {
            styled(Button(role: action.role == .destructive ? .destructive : nil) { onChoose(action) } label: { label },
                   action: action, isSelected: isSelected)
        } else {
            // A split button: the action, and its other versions in ▾.
            styled(Menu {
                ForEach(action.alternatives) { alternative in
                    Button(alternative.title, role: alternative.role == .destructive ? .destructive : nil) { onChoose(alternative) }
                }
            } label: { label } primaryAction: { onChoose(action) }
                .menuStyle(.button)
                .fixedSize(),
                   action: action, isSelected: isSelected)
        }
    }

    /// Style by meaning: destructive red, the safe default prominent,
    /// everything else plain. The keyboard's choice wears a ring.
    @ViewBuilder
    private func styled(_ control: some View, action: DecisionAction, isSelected: Bool) -> some View {
        let base = control
        .overlay {
            // The keyboard's choice, once the keyboard is choosing.
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(theme.chat.accent, lineWidth: 1.5)
                .padding(-2.5)
                .opacity(isSelected && showsSelectionRing ? 1 : 0)
                .animation(.easeOut(duration: 0.1), value: isSelected)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])

        if action.role == .destructive {
            base.buttonStyle(.borderedProminent).tint(theme.chat.destructive)
        } else if action.id == request.defaultActionID, action.role == .normal {
            base.buttonStyle(.borderedProminent).tint(theme.chat.accent)
        } else {
            base.buttonStyle(.bordered)
        }
    }
}

/// Where a panel shows its decision: the bottom zone the toast uses, with
/// the toast's width, edges, surface and motion (`BottomSurface`), over the
/// footer, the content still visible above.
package struct DecisionDock: View {
    package let center: DecisionCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    package var body: some View {
        GeometryReader { geometry in
            VStack {
                Spacer(minLength: 0)
                if let request = center.current {
                    DecisionCard(request: request, selectedID: center.selectedID,
                                 showsSelectionRing: center.isNavigatingByKeyboard) { center.choose($0) }
                        .frame(maxWidth: BottomSurface.width(in: geometry.size.width))
                        .transition(BottomSurface.transition(reduceMotion: reduceMotion))
                        .id(request.id)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, BottomSurface.bottomPadding)
            .animation(BottomSurface.animation(appearing: center.current != nil), value: center.current?.id)
        }
    }
}

/// The panel's bottom zone: a decision still needed wins over a notice of
/// something that happened — never both at once.
package struct PanelBottomZone: ViewModifier {
    package let notices: NoticeCenter
    package let decisions: DecisionCenter

    package func body(content: Content) -> some View {
        content
            .overlay { TransientNoticeHost(center: notices).opacity(decisions.current == nil ? 1 : 0) }
            .overlay { DecisionDock(center: decisions) }
            .onChange(of: decisions.current?.id) { _, id in if id != nil { notices.dismiss() } }
    }

    package init(notices: NoticeCenter, decisions: DecisionCenter) {
        self.notices = notices
        self.decisions = decisions
    }
}
