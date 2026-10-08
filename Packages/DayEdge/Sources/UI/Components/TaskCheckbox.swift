import SwiftUI

/// The completion control: a 16pt ring in the list's color — deliberately
/// larger and heavier than an event's 10pt RSVP dot, so the two never read
/// as the same thing once tasks share the agenda.
package struct TaskCheckbox: View {
    @Environment(\.themePalette) private var theme
    package let color: Color
    package let isCompleted: Bool
    package var isHovering = false
    /// `ringSize` in the Tasks view, `embeddedRingSize` among events.
    package var size: CGFloat = AppTheme.Tasks.ringSize

    package var body: some View {
        ZStack {
            if isCompleted {
                Circle().fill(color)
                Image(systemName: "checkmark")
                    .font(.system(size: size / 2, weight: .bold))
                    .foregroundStyle(theme.onAccentText)
            } else {
                Circle().strokeBorder(color, lineWidth: AppTheme.Tasks.ringStroke)
                if isHovering {
                    Image(systemName: "checkmark")
                        .font(.system(size: size / 2, weight: .bold))
                        .foregroundStyle(color.opacity(theme.sourcePresentation.taskHoverCheckOpacity))
                }
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .animation(.easeOut(duration: 0.12), value: isCompleted)
    }

    package init(color: Color, isCompleted: Bool, isHovering: Bool = false, size: CGFloat = AppTheme.Tasks.ringSize) {
        self.color = color
        self.isCompleted = isCompleted
        self.isHovering = isHovering
        self.size = size
    }
}
