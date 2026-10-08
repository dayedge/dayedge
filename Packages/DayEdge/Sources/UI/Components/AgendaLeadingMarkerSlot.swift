import SwiftUI

/// The marker column of a mixed agenda row. Owns alignment only: whatever
/// marker it holds (an event's small dot, a task's larger ring) is centered
/// horizontally in a fixed-width column and vertically on the row's first
/// text line — so content always starts at the same x, and a bigger marker
/// never pushes the text or sits off-axis. The marker owns the meaning.
///
/// Use inside an `HStack(alignment: .top, spacing: AppTheme.AgendaRow.markerToContent)`.
package struct AgendaLeadingMarkerSlot<Marker: View>: View {
    @ViewBuilder package let marker: () -> Marker

    package init(@ViewBuilder marker: @escaping () -> Marker) {
        self.marker = marker
    }

    package var body: some View {
        marker()
            .frame(width: AppTheme.AgendaRow.markerSlotWidth)
            .alignmentGuide(.top) { d in d[VerticalAlignment.center] - AppTheme.AgendaRow.firstLineCenter }
    }
}
