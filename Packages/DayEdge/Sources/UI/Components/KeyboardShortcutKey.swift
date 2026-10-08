import SwiftUI

/// A keyboard key as a hint — "↵", "⇥", "esc", "⌘J" — in a small keycap.
/// Informational only: no hover, no button look. The glyph sits in a fixed
/// frame and is centered optically, not on its text baseline (↵ and ⇥ draw
/// high in the system font).
package struct KeyboardShortcutKey: View {
    @Environment(\.themePalette) private var theme

    package enum Size {
        /// The full-screen meeting takeover.
        case large
        /// The command palette's footer.
        case compact
    }

    package let text: String
    package var size: Size = .compact
    package var onAccent = false

    package init(_ text: String, size: Size = .compact, onAccent: Bool = false) {
        self.text = text
        self.size = size
        self.onAccent = onAccent
    }

    package var body: some View {
        switch size {
        case .large:
            Text(text)
                .font(AppTheme.Keycap.largeFont)
                .foregroundStyle(onAccent ? theme.keycap.onAccentLargeGlyph : theme.keycap.largeGlyph)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .offset(y: Self.opticalOffset(text, size: 13))
                .background(onAccent ? theme.keycap.onAccentLargeFill : theme.keycap.largeFill, in: RoundedRectangle(cornerRadius: AppTheme.Keycap.largeRadius))
        case .compact:
            let shape = RoundedRectangle(cornerRadius: AppTheme.Keycap.compactRadius, style: .continuous)
            Text(text)
                .font(AppTheme.Keycap.compactFont)
                .foregroundStyle(theme.keycap.compactGlyph)
                .offset(y: Self.opticalOffset(text, size: 10))
                // Single glyphs share one square-ish key; "esc", "⌘J" grow.
                .padding(.horizontal, text.count > 1 ? 4 : 0)
                .frame(minWidth: AppTheme.Keycap.compactMinWidth, minHeight: AppTheme.Keycap.compactHeight,
                       maxHeight: AppTheme.Keycap.compactHeight)
                .background(shape.fill(theme.keycap.compactFill))
                .overlay(shape.strokeBorder(theme.keycap.compactStroke, lineWidth: 0.5))
        }
    }

    /// Arrow glyphs sit above the optical middle of the line; nudge them
    /// down a little (proportional to the font size).
    private static func opticalOffset(_ text: String, size: CGFloat) -> CGFloat {
        ["↵", "↩", "⇥", "⇤"].contains(text) ? size * 0.08 : 0
    }
}

/// A keycap and what it does: "[↵] Create". One unit in a shortcut footer.
package struct KeyboardShortcutHint: View {
    @Environment(\.themePalette) private var theme

    package let key: String
    package let action: String
    package var accessibilityLabel: String?

    package var body: some View {
        HStack(spacing: 5) {
            KeyboardShortcutKey(key)
            Text(action)
                .font(AppTheme.Keycap.actionLabelFont)
                .foregroundStyle(theme.keycap.actionLabel)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel ?? "\(action), \(key)")
    }

    package init(key: String, action: String, accessibilityLabel: String? = nil) {
        self.key = key
        self.action = action
        self.accessibilityLabel = accessibilityLabel
    }
}
