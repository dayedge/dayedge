import SwiftUI
import Domain

/// The month grid's hover "quick glance": a single day's mini-agenda,
/// built from the exact same header/row components the real agenda list
/// uses (`AgendaDayHeaderView`/`AgendaEventRowView`), just scoped to one
/// day and capped in height with the shared native the app scroll view.
package struct DayGlanceView: View {
    @Environment(\.themePalette) private var theme

    package let date: Date
    package let events: [AgendaEventModel]
    package let isToday: Bool
    /// Reported so the owner can factor "is the user still interacting
    /// with the glance card itself" into whether to keep it open — moving
    /// the mouse from the triggering day cell into this popover otherwise
    /// reads as "left the grid" and would dismiss it out from under you.
    package var onHoverChange: (Bool) -> Void = { _ in }

    private var nonCancelledCount: Int {
        events.filter { $0.status != .cancelled }.count
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AgendaDayHeaderView(
                date: date,
                isToday: isToday,
                eventCount: nonCancelledCount,
                style: .popoverAgenda
            )

            if events.isEmpty {
                Text(L10n.tr("dayglanceview.no.events", "No events"))
                    .font(AppTheme.TextStyle.eventSubtitle)
                    .foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, AppTheme.horizontalPadding)
                    .padding(.vertical, 12)
            } else {
                ThemedScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(events) { event in
                            AgendaEventRowView(event: event, date: date)
                        }
                    }
                    .padding(.vertical, 4)
                }
                // Compact: shows roughly 4 events before scrolling rather
                // than always reserving space for the whole list.
                .frame(height: min(CGFloat(events.count) * 58 + 8, 260))
            }
        }
        .frame(width: 300)
        // Native popover chrome owns the whole surface, including its arrow.
        // Painting a themed rectangle here creates a seam against that arrow.
        .onHover(perform: onHoverChange)
    }

    package init(date: Date, events: [AgendaEventModel], isToday: Bool, onHoverChange: @escaping (Bool) -> Void = { _ in }) {
        self.date = date
        self.events = events
        self.isToday = isToday
        self.onHoverChange = onHoverChange
    }
}
