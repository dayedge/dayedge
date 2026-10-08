import CoreGraphics
import SwiftUI

/// Where a tooltip of `size` goes next to `anchor` (both in screen
/// coordinates, AppKit's bottom-up space): on the preferred edge with a
/// small gap, flipped when that edge has no room, centered horizontally on
/// the anchor and clamped inside the screen.
package enum TooltipPlacement {
    package static let gap: CGFloat = 6
    package static let screenMargin: CGFloat = 4

    package static func frame(for size: CGSize, anchor: CGRect, edge: Edge, screen: CGRect) -> (frame: CGRect, edge: Edge) {
        func origin(for edge: Edge) -> CGPoint {
            // `.top` means visually above the anchor, i.e. larger y here.
            let y = edge == .bottom ? anchor.minY - gap - size.height : anchor.maxY + gap
            return CGPoint(x: anchor.midX - size.width / 2, y: y)
        }
        func fits(_ point: CGPoint) -> Bool {
            point.y >= screen.minY + screenMargin && point.y + size.height <= screen.maxY - screenMargin
        }

        var chosen = edge == .bottom ? Edge.bottom : .top
        var point = origin(for: chosen)
        if !fits(point) {
            let flipped: Edge = chosen == .bottom ? .top : .bottom
            let alternative = origin(for: flipped)
            if fits(alternative) {
                chosen = flipped
                point = alternative
            }
        }
        let maxX = screen.maxX - screenMargin - size.width
        point.x = min(max(point.x, screen.minX + screenMargin), max(maxX, screen.minX + screenMargin))
        return (CGRect(origin: point, size: size), chosen)
    }
}
