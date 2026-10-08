import SwiftUI
import Domain
import UI

/// The Day view's ALL-DAY lane — a dedicated band above the hourly
/// timeline, not a row on it. Structurally mirrors `HourGridBackgroundView`'s
/// own per-hour row (same horizontal padding, same label width, same
/// gutter spacing) so the all-day label and its events line up exactly
/// with the hour labels and grid content below, rather than drifting off
/// on their own alignment.
package struct AllDayRowView: View {
    @Environment(\.themePalette) private var theme

    package let date: Date
    package var events: [AgendaEventModel] = []
    package var topPadding: CGFloat = 10
    /// Day view keyboard selection, and the Return-key detail request.
    package var selectedEventID: String?
    package var detailPresentationRequest: EventDetailPresentationRequest?
    package var onDetailPresentationChange: (String, Bool) -> Void = { _, _ in }

    @State private var isExpanded = false

    private static let collapsedVisibleCount = 3
    private static let rowSpacing: CGFloat = 4
    private static let trailingMargin: CGFloat = 10

    private var visibleEvents: [AgendaEventModel] {
        isExpanded ? events : Array(events.prefix(Self.collapsedVisibleCount))
    }

    private var overflowCount: Int {
        max(events.count - Self.collapsedVisibleCount, 0)
    }

    /// A compact, localized label sized for the hour-label gutter.
    private var gutterLabel: some View {
        Text(L10n.tr("agenda.all.day", "all-day"))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(theme.secondaryText)
            // Keep longer translations inside the gutter rather than overflowing the panel.
            .lineLimit(1)
            .frame(width: AppTheme.Metrics.timelineLabelGutterWidth, alignment: .trailing)
    }

    package var body: some View {
        if !events.isEmpty, let firstEvent = visibleEvents.first {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: Self.rowSpacing) {
                    // The label lives in its own row, alongside only the
                    // first event tag, so the HStack's default `.center`
                    // alignment vertically centers it on that one row —
                    // not on the lane as a whole once more rows are added.
                    HStack(alignment: .center, spacing: AppTheme.Metrics.timelineGutterSpacing) {
                        gutterLabel
                        tag(firstEvent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ForEach(visibleEvents.dropFirst()) { event in
                        tag(event)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, contentLeadingInset)
                    }

                    if !isExpanded, overflowCount > 0 {
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) { isExpanded = true }
                        } label: {
                            Text(L10n.tr("agenda.overflow", "+\(overflowCount) more"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(theme.secondaryText)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, contentLeadingInset + 2)
                    }
                }
                .padding(.trailing, Self.trailingMargin)
                .padding(.horizontal, AppTheme.Metrics.timelineHorizontalInset)
                .padding(.top, topPadding)
                .padding(.bottom, 9)

                Rectangle()
                    .fill(theme.chrome.gridRule)
                    .frame(height: 1)
                    .padding(.horizontal, AppTheme.Metrics.timelineHorizontalInset)
            }
            // Collapses back to 3 rows on a fresh day rather than staying
            // stuck open from whatever the previously displayed day left it at.
            .onChange(of: date) { _, _ in isExpanded = false }
            // Keyboard selection never lands on a folded-away event.
            .onChange(of: selectedEventID) { _, id in
                guard let id, let index = events.firstIndex(where: { $0.id == id }),
                      index >= Self.collapsedVisibleCount else { return }
                isExpanded = true
            }
        }
    }

    private func tag(_ event: AgendaEventModel) -> some View {
        AllDayEventTagView(
            event: event,
            date: date,
            detailPresentationRequest: detailPresentationRequest,
            onDetailPresentationChange: { onDetailPresentationChange(event.id, $0) },
            isKeyboardSelected: selectedEventID == event.id
        )
    }

    private var contentLeadingInset: CGFloat {
        AppTheme.Metrics.timelineLabelGutterWidth + AppTheme.Metrics.timelineGutterSpacing
    }
}
