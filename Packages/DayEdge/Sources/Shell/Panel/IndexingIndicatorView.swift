import SwiftUI
import Domain

/// The bottom selector's leading status segment while the calendar index
/// fills (`BottomContextSelector`): up only for refreshes that take a while
/// (`showsIndicator` waits before revealing). While filling it spins (hover
/// shows ⏸); a click pauses the background filling of other years, and it
/// then stays up with ▶ to resume. Hovering shows live progress in
/// The app's tooltip bubble.
///
/// Informational for the keyboard and VoiceOver — not a focus target of
/// its own; the selector announces the indexing state as its value.
struct IndexingStatusSegment: View {
    @Environment(\.themePalette) private var theme

    let activity: CalendarIndexActivity
    let side: CGFloat
    @State private var isHovered = false

    var body: some View {
        glyph
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .onTapGesture { activity.togglePause() }
            .onHover { isHovered = $0 }
            .hoverTooltip(isPresented: isHovered, edge: .top) {
                IndexingProgressTooltip(activity: activity)
            }
            .accessibilityHidden(true)
    }

    /// What the selector announces while indexing.
    static func accessibilityStatus(_ activity: CalendarIndexActivity) -> String {
        activity.isPaused ? L10n.tr(
            "indexingindicatorview.calendar.indexing.paused", "Calendar indexing paused"
        ) : L10n.tr(
            "indexingindicatorview.indexing.calendars", "Indexing calendars"
        )
    }

    @ViewBuilder
    private var glyph: some View {
        if activity.isPaused {
            Image(systemName: "play.fill")
                .font(.system(size: 11, weight: .semibold))
        } else if isHovered {
            Image(systemName: "pause.fill")
                .font(.system(size: 11, weight: .semibold))
        } else {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(theme.primaryText)
        }
    }
}

/// Live while open: reads `activity` directly, so the bubble updates as
/// chunks land. Fixed width so the panel never resizes under the pointer.
private struct IndexingProgressTooltip: View {
    @Environment(\.themePalette) private var theme

    let activity: CalendarIndexActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.primaryText)
            if let fraction = activity.fraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                    .tint(activity.isPaused ? theme.secondaryText : theme.controlAccent)
                Text(L10n.tr("index.progress.months", "\(Int((fraction * 100).rounded()))% · \(activity.coveredChunks) of \(activity.totalChunks) calendar-months"))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(theme.secondaryText)
            }
            if let detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(activity.isPaused ? L10n.tr("indexingindicatorview.click.to.resume", "Click to resume.") : L10n.tr("indexingindicatorview.click.to.pause", "Click to pause."))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.primaryText.opacity(0.8))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 240, alignment: .leading)
    }

    private var title: String {
        if activity.isPaused { return L10n.tr("indexingindicatorview.calendar.indexing.paused", "Calendar indexing paused") }
        return activity.isIndexing ? L10n.tr(
            "indexingindicatorview.updating.calendar.index", "Updating calendar index"
        ) : L10n.tr(
            "indexingindicatorview.calendar.index.up.to.date", "Calendar index up to date"
        )
    }

    private var detail: String? {
        if activity.isPaused {
            return L10n.tr("indexingindicatorview.other.years.wait.this.month.b55c07", "Other years wait; this month and your changes still update.")
        }
        switch activity.pacing {
        case .lowPower: return L10n.tr("indexingindicatorview.older.and.future.years.fill.6e2b5b", "Older and future years fill slowly in Low Power Mode.")
        case .thermal: return L10n.tr("indexingindicatorview.slowed.down.while.the.mac.is.running.hot", "Slowed down while the Mac is running hot.")
        case .normal:
            if activity.isNearReady, (activity.fraction ?? 1) < 1 { return L10n.tr(
                "indexingindicatorview.this.month.is.ready.filling.other.years", "This month is ready; filling other years."
            ) }
            return activity.fraction == 1 ? L10n.tr("indexingindicatorview.checking.for.changes", "Checking for changes…") : nil
        }
    }
}
