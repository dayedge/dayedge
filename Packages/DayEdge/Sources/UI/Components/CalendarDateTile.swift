import SwiftUI
import Domain

/// A tiny calendar page: the weekday on a red band (white text), then the
/// day number and the month — with a short year only when it isn't this
/// year. Dates search results and Ask's events and tasks.
package struct CalendarDateTile: View {
    @Environment(\.themePalette) private var theme
    @Environment(\.dateFormatter) private var dateFormatter

    package let date: Date
    package var isToday = false
    package var showsYear = false
    package var calendar: Calendar = .autoupdatingCurrent

    private var dates: DatePresentationFormatter { dateFormatter.with(calendar) }

    private var weekday: String {
        dates.weekday(date, .abbreviated).uppercased()
    }

    private var day: String {
        dates.day(date)
    }

    /// "Dec", or "Dec 27" outside this year.
    private var month: String {
        let month = dates.month(date, abbreviated: true)
        return showsYear ? "\(month) \(dates.format(date, .custom("yy")))" : month
    }

    package var body: some View {
        VStack(spacing: 0) {
            Text(weekday)
                .font(AppTheme.DateTile.weekdayFont)
                .foregroundStyle(theme.dateTile.weekdayTint)
                .frame(maxWidth: .infinity)
                .frame(height: AppTheme.DateTile.weekdayBandHeight)
                .background(theme.dateTile.weekdayBand)
            VStack(spacing: -1) {
                Text(day)
                    .font(AppTheme.DateTile.dayFont)
                    .foregroundStyle(isToday ? theme.dateTile.todayTint : theme.dateTile.dayTint)
                Text(month)
                    .font(AppTheme.DateTile.monthFont)
                    .foregroundStyle(theme.dateTile.monthTint)
            }
            .frame(maxHeight: .infinity)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(width: AppTheme.DateTile.tileWidth, height: AppTheme.DateTile.tileHeight)
        .background(theme.dateTile.tileFill)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.DateTile.tileRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.DateTile.tileRadius, style: .continuous)
                .strokeBorder(theme.dateTile.tileBorder, lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dates.format(date, .standard))
    }

    package init(date: Date, isToday: Bool = false, showsYear: Bool = false, calendar: Calendar = .autoupdatingCurrent) {
        self.date = date
        self.isToday = isToday
        self.showsYear = showsYear
        self.calendar = calendar
    }
}
