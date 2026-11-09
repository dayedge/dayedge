import SwiftUI
import Domain
import UI

/// The Command Window's Day heading: "Monday 26" in the primary colour and
/// the day's counts under it. The sidebar's month (and its chevrons) gives
/// the rest; when the sidebar shows another month, the heading names the
/// day's own ("Monday 26 Oct", its year outside the current one).
package struct DayPaneHeading: View {
    @Environment(\.themePalette) private var theme
    @Environment(\.dateFormatter) private var dateFormatter

    package let facts: DayHeaderFacts
    /// The month the sidebar shows.
    package let shownMonth: Date
    package let onToday: () -> Void

    private var title: String {
        Calendar.autoupdatingCurrent.isDate(facts.date, equalTo: shownMonth, toGranularity: .month)
            ? dateFormatter.weekdayDay(facts.date)
            : dateFormatter.format(facts.date, .compact)
    }

    package var body: some View {
        // The sidebar's month heading centres its title on its chevrons;
        // the same trailing geometry, unseen, keeps both titles (and their
        // counts) on one line.
        LargeTitleHeader(trailingAlignment: .center) {
            Button(action: onToday) {
                Text(title)
                    .font(theme.calendarHeader.titleFont)
                    .foregroundStyle(theme.primaryText)
            }
            .buttonStyle(.plain)
            .todayTooltip()
        } subtitle: {
            PeriodHeaderSubtitle(text: DayHeaderView.countText(events: facts.eventCount, tasks: facts.taskCount))
        } trailing: {
            PeriodStepper(onPrevious: {}, onNext: {})
                .hidden()
                .accessibilityHidden(true)
        }
    }

    package init(facts: DayHeaderFacts, shownMonth: Date, onToday: @escaping () -> Void) {
        self.facts = facts
        self.shownMonth = shownMonth
        self.onToday = onToday
    }
}
