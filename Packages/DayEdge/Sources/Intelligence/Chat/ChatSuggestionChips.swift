import AppKit
import SwiftUI
import UI

/// The empty conversation's suggestions: a 2×2 grid of identical, neutral
/// capsules just above the composer. Monochrome on purpose — orange, red
/// and blue already mean events, now/overdue and today/you.
package struct ChatSuggestionChips: View {
    package let onChoose: (ChatSuggestion) -> Void

    package var body: some View {
        let suggestions = ChatSuggestion.allCases
        Grid(horizontalSpacing: AppTheme.Chat.chipSpacing, verticalSpacing: AppTheme.Chat.chipSpacing) {
            ForEach(Array(stride(from: 0, to: suggestions.count, by: 2)), id: \.self) { start in
                GridRow {
                    ForEach(suggestions[start..<min(start + 2, suggestions.count)]) { suggestion in
                        Button { onChoose(suggestion) } label: {
                            ChipLabel(symbol: suggestion.symbol, text: suggestion.label)
                        }
                        .buttonStyle(ChipButtonStyle())
                        .accessibilityHint(suggestion.prompt)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ChipLabel: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: AppTheme.Chat.chipIconGap) {
            // The chip sets two whites: the label takes the primary one, the
            // symbol the quieter secondary one.
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }
}

/// Every chip, the same: capsule, neutral fill and hairline; brighter on
/// hover, pressed a touch smaller, an accent focus ring for the keyboard.
private struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ChipBody(configuration: configuration)
    }

    private struct ChipBody: View {
        @Environment(\.themePalette) private var theme
        let configuration: Configuration
        @State private var isHovering = false
        @Environment(\.isFocused) private var isFocused
        @Environment(\.colorSchemeContrast) private var contrast

        var body: some View {
            let chat = theme.chat
            configuration.label
                .foregroundStyle(isHovering ? chat.chipLabelHover : chat.chipLabel,
                                 isHovering ? chat.chipIconHover : chat.chipIcon)
                .padding(.horizontal, AppTheme.Chat.chipPaddingH)
                .frame(height: AppTheme.Chat.chipHeight)
                .background(Capsule().fill(configuration.isPressed ? chat.chipPressedFill : (isHovering ? chat.chipHoverFill : chat.chipFill)))
                .overlay(Capsule().strokeBorder(contrast == .increased ? chat.chipBorderIncreased : chat.chipBorder, lineWidth: 0.5))
                .overlay(Capsule().strokeBorder(chat.accent, lineWidth: 2).opacity(isFocused ? 1 : 0))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .contentShape(Capsule())
                .animation(.easeOut(duration: 0.12), value: isHovering)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
                .onHover { hovering in
                    isHovering = hovering
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                .focusEffectDisabled()
        }
    }
}
