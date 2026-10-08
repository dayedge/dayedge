import SwiftUI
import Domain

extension AgendaEventRowView {
    /// Time, title and subtitle for the row's density.
    @ViewBuilder
    var details: some View {
        if density == .regular {
            VStack(alignment: .leading, spacing: 2) {
                if !event.isAllDay { timeLine }
                titleText
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = event.subtitle {
                    Text(subtitle)
                        .font(AppTheme.TextStyle.eventSubtitle)
                        .foregroundStyle(subtitleColor)
                        .strikethrough(event.status == .cancelled)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        } else {
            // A reference, not a full row: time, title and the same
            // glyphs on one line; details are one click away.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let compactTimeColumnWidth {
                    Group { if !event.isAllDay { timeLine } else { Text(" ").font(AppTheme.TextStyle.eventTime) } }
                        .lineLimit(1)
                        .frame(width: compactTimeColumnWidth, alignment: .leading)
                } else if !event.isAllDay {
                    timeLine
                }
                if compactTitleFades {
                    titleText.fadingOverflow()
                } else {
                    titleText
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }

    @ViewBuilder
    var statusIndicator: some View {
        switch event.status {
        case .confirmed:
            Circle()
                .fill(event.color)
                .frame(width: 10, height: 10)
        case .tentative:
            Circle()
                .strokeBorder(event.color.opacity(theme.sourcePresentation.tentativeMarkerOpacity), style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                .frame(width: 10, height: 10)
        case .cancelled:
            Circle()
                .strokeBorder(theme.dimmedText, lineWidth: 1.5)
                .frame(width: 10, height: 10)
        case .untimed:
            Circle()
                .fill(theme.secondaryText)
                .frame(width: 6, height: 6)
                .padding(2)
        }
    }
}
