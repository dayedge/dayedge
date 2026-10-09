import SwiftUI
import UI

/// Ask — the app's fourth view, upside down from a usual chat:
/// the composer sits in the toolbar row (where the other views have the
/// search field), the conversation runs newest message first below it,
/// and the footer is the panel's usual one (chats instead of calendars,
/// and the gear).
///
/// Owns only its reveal choreography: `isPresented` flips as the view is
/// switched to or away from, and each part follows at its own pace. A
/// query asked from the search field arrives already sent.
package struct ChatView<Footer: View>: View {
    @Environment(\.themePalette) private var theme

    package let session: ChatSession
    /// Whether Ask is the view on screen.
    package let isPresented: Bool
    /// Where referenced events and tasks come from, and their actions.
    package let objects: ChatObjectContext
    /// The panel's footer: the chats pill and the gear.
    @ViewBuilder package let footer: () -> Footer

    package init(session: ChatSession, isPresented: Bool, objects: ChatObjectContext, @ViewBuilder footer: @escaping () -> Footer) {
        self.session = session
        self.isPresented = isPresented
        self.objects = objects
        self.footer = footer
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isComposerFocused: Bool
    @State private var isRevealed = false
    /// Whether the jump-to-latest arrow shows.
    @State private var follow = ChatScrollFollow()

    package var body: some View {
        ChatTranscriptView(messages: session.messages, objects: objects, approvals: session.approvals,
                           isComposerEmpty: session.draft.isEmpty, follow: follow, isActive: isPresented)
            .frame(maxHeight: .infinity)
            // Scrolled well down: a way back to the newest message,
            // floating over the conversation just under the composer (the
            // bars' safe area) — never moving anything.
            .overlay(alignment: .topTrailing) {
                ChatJumpToLatestButton(follow: follow)
                    .padding(.trailing, AppTheme.horizontalPadding)
                    .padding(.top, AppTheme.Chat.jumpButtonGap)
            }
            .opacity(isRevealed ? 1 : 0)
            .animation(timing(isRevealed ? 0.16 : 0.12), value: isRevealed)
            .floatingTopBar(usesNativeEffect: false) {
                VStack(alignment: .leading, spacing: AppTheme.Chat.chipsToComposer) {
                    ChatComposerView(
                        draft: Binding(get: { session.draft }, set: { session.draft = $0 }),
                        canSend: session.canSend,
                        isResponding: session.isResponding,
                        focus: $isComposerFocused,
                        onSend: send,
                        onStop: { session.stop() }
                    )
                    // Arriving, it grows out of the search field's spot (same
                    // row, same glyph position) into the full row; leaving,
                    // it folds back into it. Laid out at its full width the
                    // whole time and revealed from the leading edge, so the
                    // text never rewraps mid-move.
                    .mask(alignment: .leading) {
                        RoundedRectangle(cornerRadius: PanelFieldSurface.cornerRadius, style: .continuous)
                            .frame(width: composerRevealWidth)
                            // Room for the field's shadow, on every side.
                            .padding(.vertical, -Self.shadowRoom)
                            .offset(x: -Self.shadowRoom)
                            .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.88), value: isRevealed)
                    }
                    .opacity(isRevealed ? 1 : 0)
                    .animation(timing(isRevealed ? 0.18 : 0.12), value: isRevealed)
                    .padding(.leading, SearchBarView.surfaceHorizontalInset)
                    // Border to border, like the open search palette; the
                    // folded view switcher floats over its end, text and all.
                    .padding(.trailing, SearchBarView.surfaceHorizontalInset)
                    // Suggestions sit right under the composer, and only
                    // until something is asked.
                    if session.isEmpty {
                        ChatSuggestionChips { suggestion in ask(suggestion.prompt) }
                            .padding(.horizontal, AppTheme.Chat.composerInset)
                            .transition(.opacity)
                            .opacity(isRevealed ? 1 : 0)
                            .animation(timing(0.2, delay: isRevealed ? 0.12 : 0), value: isRevealed)
                    }
                }
                .padding(.top, PanelToolbarMetrics.topInset)
                .padding(.bottom, AppTheme.Chat.composerInset)
            }
            .floatingFooterBar(usesNativeEffect: false) {
                footer()
                    .opacity(isRevealed ? 1 : 0)
                    .animation(timing(0.16), value: isRevealed)
            }
            .background(theme.contentBackdrop.opacity(isRevealed ? 1 : 0).animation(timing(0.14), value: isRevealed))
            .onAppear {
                isRevealed = isPresented
                // The query has already been sent: typing goes to the composer.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { if isPresented { isComposerFocused = true } }
            }
            .onChange(of: isPresented) { _, presented in
                isRevealed = presented
                // Switching to Ask means typing to it.
                isComposerFocused = presented
            }
    }

    /// Beyond the composer on every side, so the reveal mask never cuts
    /// its shadow (the search surface's, softer and longer in light themes).
    private static var shadowRoom: CGFloat { 40 }

    /// How much of the composer shows: all of it (and its shadow) once
    /// Ask is on screen; about the collapsed search field's width while it
    /// arrives from it or leaves into it.
    private var composerRevealWidth: CGFloat {
        guard !isRevealed, !reduceMotion else {
            return AppTheme.Metrics.popoverWidth + 2 * Self.shadowRoom
        }
        return Self.shadowRoom + AppTheme.Chat.composerArrivingWidth
    }

    /// Every send runs in the collapse's animation (the suggestions go).
    private func send() {
        // Plain Return never answers a card (that's ⌘↩): it's "send", and a
        // half-typed follow-up mustn't approve a change.
        guard session.approvals.pending == nil else { return }
        withAnimation(ChatAnimation.collapse(reduceMotion: reduceMotion)) { session.sendDraft() }
    }

    /// A suggestion is sent as-is, straight away.
    private func ask(_ prompt: String) {
        withAnimation(ChatAnimation.collapse(reduceMotion: reduceMotion)) { session.start(with: prompt) }
    }

    private func timing(_ duration: Double, delay: Double = 0) -> Animation {
        .easeOut(duration: duration).delay(reduceMotion ? 0 : delay)
    }
}

/// How a conversation changes (a send, a new or reopened chat).
package enum ChatAnimation {
    package static func collapse(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.9)
    }
}

/// The round ↑ that brings the transcript back to the newest message:
/// very translucent glass, shown only once the reader is well down from
/// the top — it fades in gently and out once they're back.
private struct ChatJumpToLatestButton: View {
    @Environment(\.themePalette) private var theme

    let follow: ChatScrollFollow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if follow.showsJump {
                Button { follow.jumpToLatest() } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.primaryText.opacity(0.85))
                        .frame(width: AppTheme.Chat.jumpButtonSize, height: AppTheme.Chat.jumpButtonSize)
                        .jumpButtonGlass(theme: theme)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(L10n.tr("chatview.jump.to.latest", "Jump to latest"))
                .accessibilityLabel(L10n.tr("chatview.jump.to.latest.message", "Jump to latest message"))
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: follow.showsJump ? 0.3 : 0.2), value: follow.showsJump)
    }
}

private extension View {
    /// Clear Liquid Glass on macOS 26; a thin material before.
    @ViewBuilder
    func jumpButtonGlass(theme: ThemePalette) -> some View {
        #if HAS_MACOS26_SDK
        if #available(macOS 26.0, *) {
            self.glassEffect(.clear.interactive(), in: Circle())
        } else {
            self.background(.ultraThinMaterial, in: Circle()).overlay(Circle().strokeBorder(theme.chat.jumpButtonBorder, lineWidth: 0.5))
        }
        #else
        self.background(.ultraThinMaterial, in: Circle()).overlay(Circle().strokeBorder(theme.chat.jumpButtonBorder, lineWidth: 0.5))
        #endif
    }
}
