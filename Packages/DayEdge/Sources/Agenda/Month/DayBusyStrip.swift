import SwiftUI
import Domain
import UI

/// A day's shape on one line: its meetings across the workday, so free
/// time shows at a glance. Where meetings overlap, the earlier one keeps
/// the time — one line, never stacked. All-day, cancelled and declined
/// events take no time here (they're chips above).
enum DayBusyStrip {
    struct Segment: Equatable {
        /// Fractions of the window, 0…1.
        let start: Double
        let end: Double
        let tint: RGBAColor
    }

    static func segments(events: [AgendaEventModel], day: Date, hours: Range<Int>,
                         calendar: Calendar) -> [Segment] {
        let dayStart = calendar.startOfDay(for: day)
        guard let windowStart = calendar.date(byAdding: .hour, value: hours.lowerBound, to: dayStart),
              let windowEnd = calendar.date(byAdding: .hour, value: hours.upperBound, to: dayStart) else { return [] }
        let span = windowEnd.timeIntervalSince(windowStart)
        // Each meeting clipped to the window, as fractions, earliest first.
        let meetings = events.compactMap { event -> Segment? in
            guard event.blocksTime, let start = event.startDate, let end = event.endDate else { return nil }
            return Segment(start: max(start.timeIntervalSince(windowStart) / span, 0),
                           end: min(end.timeIntervalSince(windowStart) / span, 1), tint: event.tint)
        }
        .sorted { $0.start < $1.start }
        var cursor = 0.0
        var segments: [Segment] = []
        for meeting in meetings {
            let start = max(meeting.start, cursor)
            guard meeting.end > start else { continue }
            segments.append(Segment(start: start, end: meeting.end, tint: meeting.tint))
            cursor = meeting.end
        }
        return segments
    }
}

/// `DayBusyStrip` drawn: a faint workday track, the meetings on it. One
/// canvas, however busy the day.
struct DayBusyStripView: View {
    @Environment(\.themePalette) private var theme
    let segments: [DayBusyStrip.Segment]

    /// Back-to-back meetings keep this apart, so they read as two.
    private static let gap: CGFloat = 1

    var body: some View {
        let workspace = theme.workspace
        Canvas { context, size in
            let radius = size.height / 2
            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: radius),
                         with: .color(workspace.gridHairline))
            for segment in segments {
                let x = segment.start * size.width
                let width = max(segment.end * size.width - x - Self.gap, size.height)
                context.fill(Path(roundedRect: CGRect(x: x, y: 0, width: width, height: size.height), cornerRadius: radius),
                             with: .color(segment.tint.color.opacity(workspace.busyStripOpacity)))
            }
        }
        .frame(height: AppTheme.CommandWindow.busyStripHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
