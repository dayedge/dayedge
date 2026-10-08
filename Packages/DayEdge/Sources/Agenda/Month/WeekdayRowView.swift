import SwiftUI
import UI

package struct WeekdayRowView: View {
    @Environment(\.themePalette) private var theme

    package let symbols: [String]

    package var body: some View {
        HStack(spacing: 0) {
            ForEach(symbols, id: \.self) { symbol in
                Text(symbol)
                    .font(AppTheme.TextStyle.weekdayLabel)
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, AppTheme.horizontalPadding)
        .padding(.top, 12)
    }
}
