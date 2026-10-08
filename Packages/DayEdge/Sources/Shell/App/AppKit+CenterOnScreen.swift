import AppKit

extension NSWindow {
    /// `NSWindow.center()` is documented to center on the screen containing
    /// "the greatest part of the window," but on this multi-monitor setup
    /// it was landing at a wildly off-screen negative coordinate instead —
    /// an invisible, unfocusable, unclickable window, which is exactly
    /// what read as "the window won't take focus." Centering against
    /// `NSScreen.main`'s actual visible frame directly sidesteps whatever
    /// `center()` was getting confused by.
    func centerOnMainScreen() {
        guard let screenFrame = NSScreen.main?.visibleFrame else {
            center()
            return
        }
        let size = frame.size
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2
        )
        setFrameOrigin(origin)
    }
}
