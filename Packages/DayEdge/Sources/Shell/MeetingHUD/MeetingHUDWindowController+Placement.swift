import AppKit
import SwiftUI
import UI

extension MeetingHUDWindowController {
    func screen(for display: MeetingHUDDisplay) -> NSScreen {
        if let fixedDisplayID,
           let screen = NSScreen.screens.first(where: { $0.stableDisplayID == fixedDisplayID }) {
            return screen
        }
        return switch display {
        case .active:
            // `NSScreen.main` ("the screen containing the focused
            // window") isn't reliable for a menu-bar-accessory app that
            // usually has no regular key window at all — resolve from
            // the mouse position instead.
            NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
                ?? NSScreen.main ?? NSScreen.screens.first!
        case .main:
            // `screens[0]` is documented to be the screen containing the
            // menu bar — the primary display.
            NSScreen.screens.first ?? NSScreen.main!
        case .all:
            NSScreen.screens.first ?? NSScreen.main!
        }
    }

    /// Factory/default: horizontally centered, ~32pt above the display's
    /// usable bottom edge. Used both when nothing has been saved yet for
    /// a display, and by "Reset Position."
    func defaultOrigin(for size: NSSize, in visibleFrame: NSRect) -> NSPoint {
        NSPoint(x: visibleFrame.midX - size.width / 2, y: visibleFrame.minY + 32)
    }

    /// Saved-or-default origin for `screen`, always clamped fully inside
    /// its current `visibleFrame` — a position saved before a resolution/
    /// Dock/display change is never trusted blindly (this is also what
    /// makes the saved position "just work" again after such a change,
    /// without a separate live-revalidation pass being required for the
    /// *not-currently-visible* case).
    func position(_ panel: NSPanel, on screen: NSScreen) {
        let visibleFrame = screen.visibleFrame
        let size = panel.frame.size
        let origin: NSPoint
        if let displayID = screen.stableDisplayID, let saved = MeetingHUDPositionStore.position(for: displayID) {
            let center = NSPoint(
                x: visibleFrame.minX + saved.xNormalized * visibleFrame.width,
                y: visibleFrame.minY + saved.yNormalized * visibleFrame.height
            )
            origin = clampedOrigin(center: center, size: size, in: visibleFrame)
        } else {
            origin = defaultOrigin(for: size, in: visibleFrame)
        }
        panel.setFrameOrigin(origin)
    }

    /// Keeps the whole HUD inside `visibleFrame` with a ~20pt margin —
    /// never partially behind the menu bar/Dock, never mostly off-screen.
    func clampedOrigin(center: NSPoint, size: NSSize, in visibleFrame: NSRect, margin: CGFloat = 20) -> NSPoint {
        let minX = visibleFrame.minX + margin
        let maxX = max(minX, visibleFrame.maxX - margin - size.width)
        let minY = visibleFrame.minY + margin
        let maxY = max(minY, visibleFrame.maxY - margin - size.height)
        let x = min(max(center.x - size.width / 2, minX), maxX)
        let y = min(max(center.y - size.height / 2, minY), maxY)
        return NSPoint(x: x, y: y)
    }
}
