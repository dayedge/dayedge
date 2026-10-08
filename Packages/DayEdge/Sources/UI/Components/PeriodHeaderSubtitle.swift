import SwiftUI

/// The single secondary line under a period title — "22 workdays" in the
/// month header, "2 events" in the day header. Both views consume this one
/// component so font, color, and title spacing can't drift apart.
package struct PeriodHeaderSubtitle: View {
    @Environment(\.themePalette) private var theme

    package let text: String

    package var body: some View {
        Text(text)
            .font(AppTheme.PeriodHeader.font)
            .foregroundStyle(theme.periodHeader.color)
            .lineLimit(1)
            .frame(height: AppTheme.PeriodHeader.subtitleHeight, alignment: .top)
    }

    package init(text: String) {
        self.text = text
    }
}
