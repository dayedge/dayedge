import SwiftUI
import Domain
import UI

package struct MonthHeaderView: View {
    @Environment(\.themePalette) private var theme

    package let monthTitle: String
    package let yearTitle: String
    /// nil hides the workday line.
    package var workdaySummary: MonthWorkdaySummary?
    package let onToday: () -> Void
    package let onPrevious: () -> Void
    package let onNext: () -> Void

    @State private var workdayHovered = false

    /// Extra header height when the workday line is shown: title→subtitle
    /// gap plus the line itself, plus the difference between the shared subtitle→content spacing.
    /// Without the line nothing is added, so no empty gap is left.
    private static let weekdayRowTopPadding: CGFloat = 12
    /// The weekday row brings its own top padding, so the subtitle sits
    /// this much closer to it than `subtitleToContent` alone would.
    private static let subtitleBottomAdjustment: CGFloat =
        AppTheme.PeriodHeader.subtitleToContent - weekdayRowTopPadding

    package var body: some View {
        // Chevrons centered on the title (Day's sit on its baseline).
        LargeTitleHeader(trailingAlignment: .center) {
            Button(action: onToday) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(monthTitle)
                        .font(theme.calendarHeader.titleFont)
                        .foregroundStyle(theme.primaryText)
                        .fixedSize()
                    Text(yearTitle)
                        .font(theme.calendarHeader.yearFont)
                        .foregroundStyle(theme.calendarHeader.yearText)
                        .fixedSize()
                }
            }
            .buttonStyle(.plain)
            // The app's own tooltip, not `.help`: the views are stacked
            // (hidden ones only faded out), and AppKit's tooltips didn't
            // follow which one is on screen — Day's never showed.
            .hoverTooltip(KeyboardCommandAction.today.title,
                             shortcut: KeyboardShortcutSettings.shared.shortcut(for: .action(.today))?.displayLabel, edge: .bottom)
        } subtitle: {
            if let summary = workdaySummary {
                workdayLine(summary)
                    .onHover { workdayHovered = $0 }
                    .hoverTooltip(isPresented: workdayHovered, edge: .bottom) {
                        workdayDetails(summary)
                    }
                    .padding(.bottom, Self.subtitleBottomAdjustment)
            }
        } trailing: {
            PeriodStepper(onPrevious: onPrevious, onNext: onNext)
        }
    }

    private func workdayLine(_ summary: MonthWorkdaySummary) -> some View {
        var text = "\(summary.workingDays) \(summary.workdayLabel)"
        if let suffix = summary.holidaySuffix { text += " · \(suffix)" }
        return PeriodHeaderSubtitle(text: text)
    }

    private func workdayDetails(_ summary: MonthWorkdaySummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(summary.breakdownLines, id: \.self) { line in
                Text(verbatim: line)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(theme.primaryText)
            }
            if !summary.holidayDetails.isEmpty {
                Divider().padding(.vertical, 4)
                ForEach(summary.holidayDetails, id: \.date) { holiday in
                    HStack(spacing: 10) {
                        Text(DatePresentationFormatter.current.format(holiday.date, .short, relativeTo: holiday.date))
                            .foregroundStyle(theme.holidayTint)
                        Text(holiday.name)
                            .foregroundStyle(theme.secondaryText)
                    }
                    .font(.system(size: 12, weight: .medium))
                }
            }
        }
        .fixedSize()
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .themedSurface(.elevated, fill: theme.background, in: Rectangle())
    }
}
