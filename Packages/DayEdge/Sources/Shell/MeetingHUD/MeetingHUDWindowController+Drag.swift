import AppKit
import SwiftUI
import UI

extension MeetingHUDWindowController {
    // MARK: - Drag to reposition

    func observeScreenChanges(_ panel: MeetingHUDPanel) {
        // Live display reconfiguration (monitor connect/disconnect,
        // resolution/scaling change, Dock move) — re-clamp a *currently
        // visible* panel immediately rather than leaving it stranded
        // until the next `show()`.
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self, weak panel] _ in
            Task { @MainActor in
                guard let self, let panel, panel.isVisible, !self.isDragging,
                      let screen = panel.screen ?? NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) })
                else { return }
                let visibleFrame = screen.visibleFrame
                let clamped = self.clampedOrigin(
                    center: NSPoint(x: panel.frame.midX, y: panel.frame.midY), size: panel.frame.size, in: visibleFrame
                )
                panel.setFrameOrigin(clamped)
            }
        }
    }

    /// Moves from a fixed mouse-down/window-origin pair in global screen
    /// coordinates. `dragRawOrigin` remains independent of the magnetically
    /// adjusted frame so attraction never feeds back into subsequent deltas.
    func handleDragChanged() {
        guard let panel else { return }
        let mouseLocation = NSEvent.mouseLocation
        if dragStartOrigin == nil {
            dragStartOrigin = panel.frame.origin
            dragStartMouseLocation = mouseLocation
            dragRawOrigin = panel.frame.origin
            isDragging = true
            panel.contentView?.layer?.removeAnimation(forKey: "revealTransform")
        }
        guard let startOrigin = dragStartOrigin,
              let startMouseLocation = dragStartMouseLocation else { return }

        let rawOrigin = NSPoint(
            x: startOrigin.x + mouseLocation.x - startMouseLocation.x,
            y: startOrigin.y + mouseLocation.y - startMouseLocation.y
        )
        dragRawOrigin = rawOrigin

        let targetScreen = fixedDisplayID.flatMap { id in
            NSScreen.screens.first { $0.stableDisplayID == id }
        } ?? NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? panel.screen
            ?? NSScreen.main
        dragTargetScreen = targetScreen

        guard let targetScreen else {
            panel.setFrameOrigin(rawOrigin)
            return
        }

        let rawCenterX = rawOrigin.x + panel.frame.width / 2
        let adjustedCenterX = magnetism.adjustedCenterX(
            rawCenterX: rawCenterX,
            targetCenterX: targetScreen.visibleFrame.midX
        )
        panel.setFrameOrigin(NSPoint(x: adjustedCenterX - panel.frame.width / 2, y: rawOrigin.y))
    }

    func handleDragEnded() {
        guard let panel else { return }
        finishDragging(panel)
        dragStartOrigin = nil
        dragStartMouseLocation = nil
        dragRawOrigin = nil
        dragTargetScreen = nil

        if let pendingRootViewWhileDragging {
            (panel.contentViewController as? NSHostingController<ThemedRoot<MeetingHUDView>>)?.rootView = ThemedRoot(content: pendingRootViewWhileDragging)
            self.pendingRootViewWhileDragging = nil
        }
    }

    /// A presentation change can hide the panel before SwiftUI delivers the
    /// gesture's `onEnded`. Do not let that leave the next presentation in a
    /// stale dragging state.
    func cancelActiveDrag() {
        guard isDragging || dragStartOrigin != nil else { return }
        isDragging = false
        dragStartOrigin = nil
        dragStartMouseLocation = nil
        dragRawOrigin = nil
        dragTargetScreen = nil
        pendingRootViewWhileDragging = nil
    }

    /// Called deterministically once per gesture. Magnetic resistance has
    /// already been visible throughout the drag; release only completes a
    /// nearby center snap, clamps on-screen, and persists the settled result.
    private func finishDragging(_ panel: MeetingHUDPanel) {
        isDragging = false

        guard let screen = dragTargetScreen
                ?? panel.screen
                ?? NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) })
        else { return }
        let visibleFrame = screen.visibleFrame
        let size = panel.frame.size
        var center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)

        let rawCenterX = (dragRawOrigin?.x ?? panel.frame.origin.x) + size.width / 2
        if magnetism.shouldSettleOnCenter(rawCenterX: rawCenterX, targetCenterX: visibleFrame.midX) {
            center.x = visibleFrame.midX
        }

        let settledFrame = NSRect(origin: clampedOrigin(center: center, size: size, in: visibleFrame), size: size)
        if settledFrame != panel.frame {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.snapSettleDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(settledFrame, display: true)
            }
        }

        guard let displayID = screen.stableDisplayID else { return }
        let settledCenter = NSPoint(x: settledFrame.midX, y: settledFrame.midY)
        MeetingHUDPositionStore.setPosition(
            MeetingHUDPosition(
                xNormalized: min(max((settledCenter.x - visibleFrame.minX) / visibleFrame.width, 0), 1),
                yNormalized: min(max((settledCenter.y - visibleFrame.minY) / visibleFrame.height, 0), 1)
            ),
            for: displayID
        )
    }

    /// The HUD surface context menu's "Reset Position" — only for the
    /// display this HUD instance is currently on.
    func resetPosition() {
        guard let panel, let screen = panel.screen ?? NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) })
        else { return }
        if let displayID = screen.stableDisplayID {
            MeetingHUDPositionStore.resetPosition(for: displayID)
        }
        let visibleFrame = screen.visibleFrame
        let settledFrame = NSRect(origin: defaultOrigin(for: panel.frame.size, in: visibleFrame), size: panel.frame.size)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.snapSettleDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(settledFrame, display: true)
        }
    }

    private static let snapSettleDuration: CFTimeInterval = 0.13
}
