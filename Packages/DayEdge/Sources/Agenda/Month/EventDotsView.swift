import SwiftUI
import UI

/// The marker row under a day number: event dots, a "+" for more, and a
/// tick for open tasks — laid out by `DayMarkerLayout`. Each dot is filled
/// for an accepted event and a dashed outline for one not yet accepted.
package struct EventDotsView: View {
    @Environment(\.themePalette) private var theme

    package let markers: [DayMarker]

    package var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(markers.enumerated()), id: \.offset) { _, marker in
                markerView(marker)
                    .frame(width: AppTheme.dotSize, height: AppTheme.dotSize)
            }
        }
        .frame(height: 8)
    }

    // Glyphs are larger than the dot-sized slot and spill into the spacing,
    // so every marker keeps the same footprint in the row.
    @ViewBuilder
    private func markerView(_ marker: DayMarker) -> some View {
        switch marker {
        case .event(let dot):
            Circle()
                .strokeBorder(dot.color, style: dot.isFilled ? StrokeStyle(lineWidth: 0) : StrokeStyle(lineWidth: 1, dash: [1, 1]))
                .background(Circle().fill(dot.isFilled ? dot.color : .clear))
        case .moreEvents:
            Image(systemName: "plus")
                .font(.system(size: 5.5, weight: .bold))
                .foregroundStyle(theme.secondaryText)
                .accessibilityLabel(L10n.tr("eventdotsview.more.events", "More events"))
        case .task(let color):
            Image(systemName: "checkmark")
                .font(.system(size: 4.5, weight: .heavy))
                .foregroundStyle(color)
                .fixedSize()
                .accessibilityLabel(L10n.tr("eventdotsview.open.tasks", "Open tasks"))
        }
    }
}
