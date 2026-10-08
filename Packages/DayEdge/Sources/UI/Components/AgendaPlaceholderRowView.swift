import SwiftUI

/// A regular agenda row whose event is still loading: the same marker slot
/// and the same height as the real row (time line over title), faint and
/// still — swapped in place when the event arrives, so nothing moves.
package struct AgendaPlaceholderRowView: View {
    @Environment(\.themePalette) private var theme

    package var body: some View {
        HStack(alignment: .top, spacing: AppTheme.AgendaRow.markerToContent) {
            AgendaLeadingMarkerSlot {
                Circle()
                    .fill(theme.chrome.gridRule)
                    .frame(width: 10, height: 10)
            }
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(theme.chrome.rowHover).frame(width: 74, height: 9)
                Capsule().fill(theme.chrome.gridRule).frame(width: 150, height: 11)
            }
            .padding(.top, 3)
            Spacer(minLength: 0)
        }
        .frame(height: AppTheme.AgendaRow.placeholderHeight, alignment: .top)
        .padding(.leading, AppTheme.AgendaRow.leadingInset)
        .padding(.trailing, AppTheme.horizontalPadding)
        .padding(.vertical, AgendaRowDensity.regular.verticalPadding)
        .accessibilityLabel(L10n.tr("agendaplaceholderrowview.loading", "Loading"))
    }

    package init() {
    }
}
