import SwiftUI

/// Configures the optional triangular "beak" that points from the bubble
/// toward whatever anchored it (a menu bar status item, say). Nil/absent
/// for a freestanding window with nothing to point at.
package struct BubblePointerConfig: Equatable {
    package var width: CGFloat = 22
    package var height: CGFloat = 9
}

/// How the app's root view is being presented — drives whether the bubble
/// shows a pointer, since the same view is meant to be reused both as a
/// menu-bar popover (pointing at its status item) and as a standalone
/// floating window (e.g. launched from Raycast, nothing to point at).
package enum PanelPresentationStyle: Equatable {
    case standalone
    case menuBarPopover(pointer: BubblePointerConfig = BubblePointerConfig())

    package var pointer: BubblePointerConfig? {
        switch self {
        case .standalone: return nil
        case .menuBarPopover(let pointer): return pointer
        }
    }
}

/// The triangular "beak" shape itself — a simple upward-pointing triangle,
/// sized and positioned by whoever draws it.
package struct BubblePointerShape: Shape {
    package func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }

    package init() {
    }
}
