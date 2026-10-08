import SwiftUI

/// The footer selectors' one grammar (Calendars, Lists, Chats): a passive
/// title names the content, the body selects it, and — under a separator —
/// full-width command rows act on it. Never actions in the header.
///
/// They look like the detail cards' property editors (`PropertyEditor`,
/// `ChoiceListEditor`), which read as native: the system popover material,
/// menu-sized rows, the accent highlight with light text, plain dividers.
package enum SelectorPopoverMetrics {
    package static let width: CGFloat = 236
    /// The property editor's padding.
    package static let padding: CGFloat = 12
    package static let rowPaddingH: CGFloat = 8
    /// A menu row (as `ChoiceListEditor`'s); two-line rows grow from it.
    package static let rowHeight: CGFloat = 22
    package static let rowPaddingV: CGFloat = 3
    package static let rowRadius: CGFloat = 5
    /// The leading column every row shares: a selection indicator in the
    /// body, a command's glyph (or nothing) in the footer.
    package static let iconColumn: CGFloat = 13
    package static let iconToText: CGFloat = 6
}

extension View {
    /// The property editors' surface: the system popover material on solid
    /// themes (or their working tone, when they have one), the theme's own
    /// on material ones.
    package func selectorPopoverSurface(_ theme: ThemePalette) -> some View {
        themedSurface(.elevated, fill: theme.surfaces == nil ? (theme.workingSurface ?? .clear) : theme.background,
                        in: Rectangle())
    }
}

/// A row's text color: light on the accent highlight, like a menu's.
package struct SelectorRowStyle {
    package let theme: ThemePalette
    package let isHighlighted: Bool

    package var primary: Color { isHighlighted ? theme.onAccentText : theme.primaryText }
    package var secondary: Color { isHighlighted ? theme.onAccentText.opacity(0.8) : theme.secondaryText }

    package init(theme: ThemePalette, isHighlighted: Bool) {
        self.theme = theme
        self.isHighlighted = isHighlighted
    }
}

/// The popover's name: quiet, passive, never a keyboard stop.
package struct SelectorPopoverHeader: View {
    @Environment(\.themePalette) private var theme
    package let title: String

    package var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(theme.primaryText)
            .padding(.horizontal, SelectorPopoverMetrics.rowPaddingH)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    package init(title: String) {
        self.title = title
    }
}

/// Body → commands.
package struct SelectorPopoverSeparator: View {
    @Environment(\.themePalette) private var theme

    package var body: some View {
        Divider()
            .overlay(theme.chrome.divider)
            .padding(.vertical, 5)
    }

    package init() {
    }
}

/// Passive secondary text for an empty body; not a keyboard stop.
package struct SelectorPopoverEmptyText: View {
    @Environment(\.themePalette) private var theme
    package let text: String

    package var body: some View {
        Text(text)
            .font(DetailMetrics.font)
            .foregroundStyle(theme.secondaryText)
            .padding(.horizontal, SelectorPopoverMetrics.rowPaddingH)
            .frame(height: SelectorPopoverMetrics.rowHeight)
    }

    package init(text: String) {
        self.text = text
    }
}

/// The highlight every row shares — hover and keyboard focus alike: the
/// menu's accent row.
package struct SelectorRowBackground: View {
    @Environment(\.themePalette) private var theme
    package let isFocused: Bool

    package var body: some View {
        RoundedRectangle(cornerRadius: SelectorPopoverMetrics.rowRadius, style: .continuous)
            .fill(isFocused ? theme.nativeControlAccent : .clear)
    }

    package init(isFocused: Bool) {
        self.isFocused = isFocused
    }
}

/// A footer command, like a native menu item: glyph column (empty when
/// there's no glyph, so labels line up with the rows above), label,
/// full-row target. Dimmed and skipped by the keyboard when it can't act.
package struct SelectorCommandRow: View {
    @Environment(\.themePalette) private var theme

    package var symbol: String?
    package let title: String
    package var isEnabled = true
    package let isFocused: Bool
    package let action: () -> Void

    package var body: some View {
        let style = SelectorRowStyle(theme: theme, isHighlighted: isFocused && isEnabled)
        Button(action: action) {
            HStack(spacing: SelectorPopoverMetrics.iconToText) {
                Group {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 11))
                            .foregroundStyle(style.secondary)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: SelectorPopoverMetrics.iconColumn, height: SelectorPopoverMetrics.iconColumn)
                Text(title)
                    .font(DetailMetrics.font)
                    .foregroundStyle(style.primary)
                Spacer(minLength: 0)
            }
            .opacity(isEnabled ? 1 : 0.4)
            .padding(.horizontal, SelectorPopoverMetrics.rowPaddingH)
            .frame(height: SelectorPopoverMetrics.rowHeight)
            .background(SelectorRowBackground(isFocused: isFocused && isEnabled))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    package init(symbol: String? = nil, title: String, isEnabled: Bool = true, isFocused: Bool, action: @escaping () -> Void) {
        self.symbol = symbol
        self.title = title
        self.isEnabled = isEnabled
        self.isFocused = isFocused
        self.action = action
    }
}
