import SwiftUI

/// A detail line on a day-timeline object — "⌛ 10:30 – 11:00", a location,
/// a task's list: small glyph, small text, in the object's own text color.
/// Shared by event blocks and task cards so the two read as one family.
package struct TimelineDetailLine: View {
    @Environment(\.themePalette) private var theme
    package let icon: String
    package let text: String
    package let color: Color
    package var isStruckThrough = false

    package var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color.opacity(theme.sourcePresentation.timelineGlyphOpacity))
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(color.opacity(theme.sourcePresentation.timelineMetadataOpacity))
                .strikethrough(isStruckThrough)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

/// The repeat glyph in a day-timeline object's top-trailing corner — same
/// shape, size and place on events and tasks.
package struct TimelineRecurrenceBadge: View {
    @Environment(\.themePalette) private var theme
    package let color: Color

    package var body: some View {
        Image(systemName: "repeat")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(color.opacity(theme.sourcePresentation.timelineGlyphOpacity))
            .padding(3)
    }
}
