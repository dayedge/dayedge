import SwiftUI
import UI

/// Pinned section header, styled like `AgendaDayHeaderView`. "Needs
/// attention" takes the red accent the way TODAY takes blue; list sections
/// carry a small dot in the list's color.
package struct TaskSectionHeaderView: View {
    @Environment(\.themePalette) private var theme

    package let section: TaskSection
    /// Completed only: tapping the header folds/unfolds its rows.
    package var onToggleCollapse: (() -> Void)?
    package var isCollapsed = false
    /// Clicking a landmark header focuses it (scrolls it to the top).
    package var onOpen: (() -> Void)?

    private var titleColor: Color {
        section.kind == .needsAttention ? theme.tasks.attentionTint : theme.secondaryText
    }

    package var body: some View {
        HStack(spacing: 6) {
            if let color = section.color {
                Circle().fill(color).frame(width: 7, height: 7)
            }
            Text(section.title.uppercased())
                .font(AppTheme.TextStyle.sectionHeader)
                .foregroundStyle(titleColor)
            Text("· \(section.totalCount)")
                .font(.system(size: 11))
                .foregroundStyle(theme.content.quietMetadata)
            if onToggleCollapse != nil {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.content.subduedMetadata)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, AppTheme.horizontalPadding)
        .padding(.top, 16)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A pinned boundary uses the shell material, not an opaque strip or row glass.
        // Desktop-backed blur keeps scrolling text from showing through in material themes.
        .themedSurface(.window, fill: theme.background, in: Rectangle())
        .contentShape(Rectangle())
        .onTapGesture {
            if let onOpen { onOpen() } else { onToggleCollapse?() }
        }
    }
}
