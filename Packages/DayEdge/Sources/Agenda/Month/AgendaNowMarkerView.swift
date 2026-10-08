import SwiftUI
import Domain
import UI

/// Presentation-only row placed inside today's compact Month agenda. It is
/// never added to `AgendaDaySection.events`, so counts, storage, and keyboard
/// event navigation continue to see only real calendar events.
package struct AgendaNowMarkerView: View {
    @Environment(\.themePalette) private var theme
    @Environment(\.timeFormat) private var timeFormat

    package let date: Date
    package var statusLabel: String?

    package var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(theme.accentRed)
                .frame(width: 7, height: 7)

            Text("NOW  \(timeFormat.time(date))")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.accentRed)

            Rectangle()
                .fill(theme.accentRed.opacity(0.5))
                .frame(height: 1)

            if let statusLabel {
                Text(statusLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize()
            }
        }
        .padding(.horizontal, AppTheme.horizontalPadding)
        .padding(.vertical, 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [L10n.tr("agendanowmarkerview.now", "Now, \(String(describing: timeFormat.time(date)))"), statusLabel]
                .compactMap { $0 }
                .joined(separator: ", ")
        )
    }
}
