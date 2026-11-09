import SwiftUI
import Domain
import UI

package struct DayHeaderView: View {
    @Environment(\.themePalette) private var theme
    @Environment(\.dateFormatter) private var dateFormatter

    package let date: Date
    package let isToday: Bool
    /// Count of the day's events, excluding cancelled ones — same
    /// convention as `AgendaDayHeaderView`'s badge in the month view.
    package var eventCount: Int = 0
    package var taskCount: Int = 0
    /// The title goes to today, as Month's does.
    package var onToday: () -> Void = {}
    package let onPrevious: () -> Void
    package let onNext: () -> Void

    package var body: some View {
        // Chevrons centered on the title, as in Month (on the baseline they
        // sat lower than Month's).
        LargeTitleHeader(trailingAlignment: .center) {
            // Tries the full "Sunday 31 September" form first, and only
            // steps down to an abbreviated month, then an abbreviated
            // weekday too, if the full form would actually overlap the
            // chevrons — rather than always abbreviating, or relying on
            // `.minimumScaleFactor` to shrink the whole thing uniformly.
            Button(action: onToday) {
                ViewThatFits(in: .horizontal) {
                    titleText(weekday: dateFormatter.weekday(date, .full), dayMonth: dateFormatter.dayMonth(date, abbreviated: false))
                    titleText(weekday: dateFormatter.weekday(date, .full), dayMonth: dateFormatter.dayMonth(date, abbreviated: true))
                    titleText(weekday: dateFormatter.weekday(date, .abbreviated), dayMonth: dateFormatter.dayMonth(date, abbreviated: true))
                }
            }
            .buttonStyle(.plain)
            .todayTooltip()
        } subtitle: {
            PeriodHeaderSubtitle(text: Self.countText(events: eventCount, tasks: taskCount))
        } trailing: {
            PeriodStepper(onPrevious: onPrevious, onNext: onNext)
        }
    }

    /// The popover's Day header, from the timeline's facts.
    package init(_ facts: DayHeaderFacts, onToday: @escaping () -> Void,
                 onPrevious: @escaping () -> Void, onNext: @escaping () -> Void) {
        self.date = facts.date
        self.isToday = facts.isToday
        self.eventCount = facts.eventCount
        self.taskCount = facts.taskCount
        self.onToday = onToday
        self.onPrevious = onPrevious
        self.onNext = onNext
    }

    /// The day's counts, or Month's "No events" on an empty day — so an
    /// empty day reads as empty without scrolling its 24 hours.
    static func countText(events: Int, tasks: Int, locale: Locale = AppLocalization.displayLocale) -> String {
        DayCountLabel.text(events: events, tasks: tasks, locale: locale)
            ?? L10n.tr("agendalistview.rows.no.events", "No events", locale: locale)
    }

    private func titleText(weekday: String, dayMonth: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(weekday)
                .foregroundStyle(isToday ? theme.calendarHeader.todayTitleText : theme.primaryText)
            Text(dayMonth)
                .foregroundStyle(theme.primaryText)
            Text(dateFormatter.year(date))
                .font(theme.calendarHeader.yearFont)
                .foregroundStyle(theme.calendarHeader.yearText)
        }
        .font(theme.calendarHeader.titleFont)
        .lineLimit(1)
        .fixedSize()
    }
}
