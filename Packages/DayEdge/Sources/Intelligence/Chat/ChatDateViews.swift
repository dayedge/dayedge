import SwiftUI
import UI

/// Native dates inside a chat answer: quiet calendar typography, the day
/// number as the anchor, the month grid's own weekend and holiday tints,
/// and a click that opens the day. No cards, capsules or icons.

/// The day above its events and tasks in an answer: the calendar tile
/// (opens the day in the calendar), and beside it what the day is —
/// "Tomorrow · Christmas Eve" — when it's something.
package struct ChatDayTileHeader: View {
    @Environment(\.themePalette) private var theme

    package let reference: ChatDayReference
    package let calendar: Calendar
    package let onOpen: (Date) -> Void

    @State private var isHovering = false

    package var body: some View {
        let now = Date()
        HStack(alignment: .center, spacing: 8) {
            Button { onOpen(reference.day) } label: {
                CalendarDateTile(date: reference.day, isToday: calendar.isDateInToday(reference.day),
                                 showsYear: calendar.component(.year, from: reference.day) != calendar.component(.year, from: now),
                                 calendar: calendar)
                    .opacity(isHovering ? 0.85 : 1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .help(L10n.tr("chatdateviews.show.in.calendar", "Show in Calendar"))
            .accessibilityLabel(ChatDayText.spoken(reference, calendar: calendar))
            .accessibilityHint(L10n.tr("chatdateviews.shows.this.day.in.the.calendar", "Shows this day in the calendar"))

            let extras = [ChatDayLabel.relativeWord(for: reference.day, now: now, calendar: calendar), reference.label].compactMap { $0 }
            if !extras.isEmpty {
                Text(extras.joined(separator: " · "))
                    .font(AppTheme.Chat.dateMetaFont)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
            }
        }
    }
}

/// One day on its own in an answer: "23  Wed, Dec · Tomorrow · Christmas
/// Eve" (a day with events and tasks gets `ChatDateTileColumn` instead).
package struct ChatDateHeader: View {
    @Environment(\.themePalette) private var theme

    package let reference: ChatDayReference
    package let calendar: Calendar
    package let onOpen: (Date) -> Void

    @State private var isHovering = false

    package var body: some View {
        let now = Date()
        Button { onOpen(reference.day) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(ChatDayText.dayNumber(reference.day, calendar: calendar))
                    .font(AppTheme.Chat.dateNumberFont)
                    .foregroundStyle(ChatDateStyle.numberColor(reference, theme: theme))
                Text(ChatDayText.weekdayAndMonth(reference.day, now: now, calendar: calendar))
                    .font(AppTheme.Chat.dateMetaFont)
                    .foregroundStyle(theme.secondaryText)
                ForEach(extras(now: now), id: \.self) { extra in
                    Text("· \(extra)")
                        .font(AppTheme.Chat.dateMetaFont)
                        .foregroundStyle(theme.dimmedText.opacity(1.6))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? theme.chat.dateHoverFill : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(L10n.tr("chatdateviews.show.in.calendar", "Show in Calendar"))
        .accessibilityLabel(ChatDayText.spoken(reference, calendar: calendar))
        .accessibilityHint(L10n.tr("chatdateviews.shows.this.day.in.the.calendar", "Shows this day in the calendar"))
    }

    /// The relative word near today, then what the day is.
    private func extras(now: Date) -> [String] {
        [ChatDayLabel.relativeWord(for: reference.day, now: now, calendar: calendar), reference.label].compactMap { $0 }
    }
}

/// A few days side by side, like small calendar day columns: weekday, the
/// day number, month, and what the day is. Whitespace and alignment, no
/// boxes; equal columns that stay compact.
package struct ChatDateStrip: View {
    package let days: [ChatDayReference]
    package let calendar: Calendar
    package let onOpen: (Date) -> Void

    package var body: some View {
        HStack(alignment: .top, spacing: 2) {
            ForEach(days, id: \.day) { reference in
                ChatDateColumn(reference: reference, calendar: calendar, onOpen: onOpen)
                    .frame(width: columnWidth)
            }
        }
    }

    /// Roomier for a few days, tighter for a week.
    private var columnWidth: CGFloat {
        days.count <= 4 ? AppTheme.Chat.dateColumnWide : AppTheme.Chat.dateColumnNarrow
    }
}

private struct ChatDateColumn: View {
    @Environment(\.themePalette) private var theme

    let reference: ChatDayReference
    let calendar: Calendar
    let onOpen: (Date) -> Void

    @State private var isHovering = false

    var body: some View {
        Button { onOpen(reference.day) } label: {
            VStack(spacing: 1) {
                Text(ChatDayText.weekday(reference.day, calendar: calendar))
                    .font(AppTheme.Chat.dateMetaFont)
                    .foregroundStyle(theme.secondaryText)
                Text(ChatDayText.dayNumber(reference.day, calendar: calendar))
                    .font(AppTheme.Chat.dateNumberFont)
                    .foregroundStyle(ChatDateStyle.numberColor(reference, theme: theme))
                Text(ChatDayText.month(reference.day, calendar: calendar))
                    .font(AppTheme.Chat.dateMetaFont)
                    .foregroundStyle(theme.dimmedText.opacity(1.6))
                if let label = reference.label {
                    Text(label)
                        .font(AppTheme.Chat.dateLabelFont)
                        .foregroundStyle(theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovering ? theme.chat.dateHoverFill : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(L10n.tr("chatdateviews.show.in.calendar", "Show in Calendar"))
        .accessibilityLabel(ChatDayText.spoken(reference, calendar: calendar))
        .accessibilityHint(L10n.tr("chatdateviews.shows.this.day.in.the.calendar", "Shows this day in the calendar"))
    }
}

/// Many days: grouped by month under a quiet month title, each month a
/// compact run of strips — never a full month grid.
package struct ChatDatesByMonth: View {
    @Environment(\.themePalette) private var theme

    package let days: [ChatDayReference]
    package let calendar: Calendar
    package let onOpen: (Date) -> Void

    package var body: some View {
        let now = Date()
        VStack(alignment: .leading, spacing: 8) {
            ForEach(months, id: \.first!.day) { month in
                VStack(alignment: .leading, spacing: 2) {
                    Text(ChatDayText.monthTitle(month[0].day, now: now, calendar: calendar))
                        .font(AppTheme.Chat.dateContextFont)
                        .foregroundStyle(theme.periodHeader.color)
                        .padding(.leading, 6)
                    ForEach(Array(stride(from: 0, to: month.count, by: ChatDatePresentation.stripLimit)), id: \.self) { start in
                        ChatDateStrip(days: Array(month[start..<min(start + ChatDatePresentation.stripLimit, month.count)]),
                                      calendar: calendar, onOpen: onOpen)
                    }
                }
            }
        }
    }

    private var months: [[ChatDayReference]] {
        var groups: [[ChatDayReference]] = []
        for day in days {
            if let last = groups.last?.last, calendar.isDate(last.day, equalTo: day.day, toGranularity: .month) {
                groups[groups.count - 1].append(day)
            } else {
                groups.append([day])
            }
        }
        return groups
    }
}

/// A run of days, presented by the fixed rule: one → a date reference,
/// a few → a strip, many → by month.
package struct ChatDatesView: View {
    package let days: [ChatDayReference]
    package let calendar: Calendar
    package let onOpen: (Date) -> Void

    package var body: some View {
        switch ChatDatePresentation.choose(count: days.count) {
        case .single:
            ChatDateHeader(reference: days[0], calendar: calendar, onOpen: onOpen)
        case .strip:
            ChatDateStrip(days: days, calendar: calendar, onOpen: onOpen)
        case .byMonth:
            ChatDatesByMonth(days: days, calendar: calendar, onOpen: onOpen)
        }
    }
}

package enum ChatDateStyle {
    /// The month grid's number tints.
    package static func numberColor(_ reference: ChatDayReference, theme: ThemePalette) -> Color {
        switch reference.tint {
        case .plain: return theme.primaryText
        case .weekend: return theme.weekendDayTint
        case .holiday: return theme.holidayTint
        }
    }
}
