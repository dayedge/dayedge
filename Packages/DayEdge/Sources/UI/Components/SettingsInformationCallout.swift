import SwiftUI

package struct SettingsInformationCallout: View {
    @Environment(\.themePalette) private var theme
    package let text: String
    package let symbol: String

    package init(text: String, symbol: String = "info.circle") {
        self.text = text
        self.symbol = symbol
    }

    package var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.settings.secondaryText)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(theme.settings.primaryText.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: AppTheme.Settings.groupRadius, style: .continuous).fill(theme.secondaryControl.hover))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}
