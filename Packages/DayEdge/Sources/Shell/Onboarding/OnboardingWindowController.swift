import AppKit
import SwiftUI
import UI

/// The onboarding window: titled but chrome-less, fixed size, centred.
@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?

    func show(model: OnboardingModel, appearance: AppearanceStore) {
        // Open: bring it forward. Closed with its button: start over with
        // the current state.
        if window?.isVisible == true {
            bringToFront()
            return
        }
        let hosting = NSHostingController(rootView: ThemedRoot(content: OnboardingView(model: model), appearance: appearance))
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.title = L10n.tr("onboardingwindowcontroller.welcome.to.dayedge", "Welcome to DayEdge")
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 720, height: 480))
        window.backgroundColor = NSColor(OnboardingStyle.background)
        Self.center(window)
        self.window = window
        bringToFront()
    }

    /// Back in front — after a system permission prompt took focus (DayEdge
    /// has no Dock icon to click back to).
    func bringToFront() {
        guard let window else { return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // Activation is only a request since macOS 14 and can be declined;
        // the window still comes forward.
        window.orderFrontRegardless()
    }

    /// On the display the pointer is on — where the user is looking.
    private static func center(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2))
    }

    func close() {
        window?.close()
        window = nil
    }
}
