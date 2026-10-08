import SwiftUI
import UI

/// The horizontal "current time" line, standard in every calendar day view.
/// Only meaningful when the timeline is showing today.
package struct NowIndicatorView: View {
    @Environment(\.themePalette) private var theme
    @Environment(\.timeFormat) private var timeFormat

    package let minutesSinceMidnight: Int
    package var statusLabel: String?

    private var yOffset: CGFloat {
        CGFloat(minutesSinceMidnight) / 60 * AppTheme.Metrics.timelineHourHeight
    }

    private var timeLabel: String {
        timeFormat.time(minutesSinceMidnight: minutesSinceMidnight)
    }

    package var body: some View {
        HStack(spacing: 0) {
            Text(timeLabel)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(theme.currentTimeText)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 5)
                .frame(minWidth: AppTheme.Metrics.timelineLabelGutterWidth - 5)
                .frame(height: AppTheme.Metrics.currentTimeCapsuleHeight)
                .background(Capsule().fill(theme.currentTimeCapsule))
                // Its right edge stays put where the hour labels end; a
                // longer label ("4:29pm") grows left, never into the events.
                .frame(width: AppTheme.Metrics.currentTimeCapsuleLeadingInset
                           + AppTheme.Metrics.timelineLabelGutterWidth - 5,
                       alignment: .trailing)
                .accessibilityLabel(L10n.tr("nowindicatorview.current.time", "Current time, \(String(describing: timeLabel))"))

            ZStack {
                Rectangle()
                    .fill(theme.background.opacity(0.5))
                    .frame(height: 3)
                Rectangle()
                    .fill(theme.accentRed)
                    .frame(height: 1.25)
            }
            if let statusLabel {
                Text(statusLabel)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(theme.timelineCapsule))
                    .fixedSize()
            }
        }
        .padding(.leading, AppTheme.Metrics.timelineHorizontalInset)
        .padding(.trailing, AppTheme.Metrics.timelineHorizontalInset)
        .offset(
            y: yOffset + AppTheme.Metrics.timelineHourRuleOffset
                - AppTheme.Metrics.currentTimeCapsuleHeight / 2
        )
    }
}
