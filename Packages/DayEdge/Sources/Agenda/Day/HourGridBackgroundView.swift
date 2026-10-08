import SwiftUI
import UI

/// The static hour rows and gridlines behind a day's events — 24 rows at a
/// fixed height, labeled in 24-hour HH:00 form.
package struct HourGridBackgroundView: View {
    @Environment(\.themePalette) private var theme
    @Environment(\.timeFormat) private var timeFormat

    package var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: AppTheme.Metrics.timelineGutterSpacing) {
                    Text(timeFormat.hour(hour))
                        .font(AppTheme.TextStyle.eventSubtitle.monospacedDigit())
                        .foregroundStyle(theme.secondaryText)
                        .frame(width: AppTheme.Metrics.timelineLabelGutterWidth, alignment: .trailing)

                    Rectangle()
                        .fill(theme.chrome.gridRule)
                        .frame(height: 1)
                        .padding(.top, AppTheme.Metrics.timelineHourRuleOffset)
                }
                .frame(height: AppTheme.Metrics.timelineHourHeight, alignment: .top)
            }
        }
        .padding(.horizontal, AppTheme.Metrics.timelineHorizontalInset)
    }
}
