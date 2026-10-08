import SwiftUI
import Domain

/// One outer surface treatment for the calendar popover and its detached
/// meeting/reminder surfaces. Window-owned shadows remain window-owned.
package enum FloatingSurface {
    package static let calendarRadius = AppTheme.cornerRadius
    package static let compactRadius: CGFloat = 15
    package static let reminderRadius: CGFloat = 12
}

private struct FloatingSurfaceModifier: ViewModifier {
    @Environment(\.themePalette) private var theme
    let radius: CGFloat
    let role: SurfaceRole
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .themedSurface(role, fill: theme.background, in: shape)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(
                    theme.floatingKeyline,
                    lineWidth: 1 / max(displayScale, 1)
                )
            }
    }
}

extension View {
    package func floatingSurface(radius: CGFloat, role: SurfaceRole = .window) -> some View {
        modifier(FloatingSurfaceModifier(radius: radius, role: role))
    }
}

/// The panel's bottom interaction zone, shared by its two temporary
/// surfaces: `TransientNotice` (something happened — small, one line,
/// auto-dismissing) and the docked `DecisionCard` (a decision is needed —
/// taller, persistent). Siblings: same width and edges, same surface,
/// hairline, radius, elevation and motion; only content and density
/// differ. One at a time — decision over notice over footer.
package enum BottomSurface {
    /// Edge to surface, each side.
    package static let inset: CGFloat = 16
    package static let maxWidth: CGFloat = 460
    /// Above the panel's bottom edge.
    package static let bottomPadding: CGFloat = 20
    package static let radius = FloatingSurface.compactRadius
    package static let contentPaddingH: CGFloat = 16
    package static let shadowRadius: CGFloat = 12
    package static let shadowY: CGFloat = 4

    package static func width(in available: CGFloat) -> CGFloat { min(maxWidth, available - inset * 2) }

    /// Fade with a few points of rise; fade only with Reduce Motion.
    package static func transition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(insertion: .opacity.combined(with: .offset(y: 5)),
                          removal: .opacity.combined(with: .offset(y: 3)))
    }

    /// In a bit slower than out.
    package static func animation(appearing: Bool) -> Animation { .easeOut(duration: appearing ? 0.18 : 0.14) }
}

extension View {
    /// The bottom surfaces' shared recipe: solid panel color, hairline,
    /// radius, restrained elevation.
    package func bottomSurface() -> some View {
        modifier(BottomSurfaceModifier())
    }
}

private struct BottomSurfaceModifier: ViewModifier {
    @Environment(\.themePalette) private var theme

    func body(content: Content) -> some View {
        content.floatingSurface(radius: BottomSurface.radius, role: .transient)
            .surfaceElevation(.transient, fallback: .init(color: theme.floatingShadow, radius: BottomSurface.shadowRadius, y: BottomSurface.shadowY))
    }
}
