import AppKit
import UI

/// Owns the bubble `NSWindow`'s entire lifecycle — creation/sizing, showing
/// (centered, or anchored under a status item), hiding, and click-outside
/// dismissal — split out of `AppDelegate`. Deliberately knows nothing about
/// a status item or `MenuBarBadgeIcon`: `show(_:)` takes a plain
/// screen-space geometry already resolved by the caller, so this type stays
/// usable for any anchor, not just a menu-bar button.
@MainActor
final class PopoverWindowController {
    private let window: BubbleWindow
    private let presentationStyle: PanelPresentationStyle
    private let presentationCoordinator: PopoverPresentationCoordinator
    private let hostPresentation: PanelHostPresentation?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?

    var isVisible: Bool { window.isVisible }

    init(contentViewController: NSViewController,
         presentationStyle: PanelPresentationStyle,
         size: PanelWindowSize,
         presentationCoordinator: PopoverPresentationCoordinator,
         hostPresentation: PanelHostPresentation? = nil) {
        self.presentationStyle = presentationStyle
        self.presentationCoordinator = presentationCoordinator
        self.hostPresentation = hostPresentation

        let window = BubbleWindow(contentViewController: contentViewController)
        window.styleMask = [.borderless, .resizable]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        // Set explicitly: left at its default, a transparent window lets
        // events through wherever the window server sees no opaque pixel
        // — and with layer-drawn content that changes as it scrolls, a
        // scroll partway through went to the window underneath. Set, the
        // whole frame takes them (the strip beside the pointer included).
        window.ignoresMouseEvents = false
        // Not AppKit's move-by-background: the system can start that drag
        // before the app sees the press, so dragging an event in the Day
        // view moved the whole panel (measured — even with `isMovable`
        // off). The panel moves from the empty parts of its top band (the
        // pointer, around the toolbar) through SwiftUI's `WindowDragGesture`
        // (`WindowDragBackground` in `RootView`).
        window.isMovableByWindowBackground = false
        window.level = .floating
        if presentationStyle.pointer == nil {
            // Free-floating: it opens on the Space in use, over full-screen apps too.
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        }

        window.minSize = size.minSize
        window.maxSize = size.maxSize
        window.setContentSize(size.size)
        // Restores the size the user left it at (the position is chosen per open).
        if let autosaveName = size.autosaveName { window.setFrameAutosaveName(autosaveName) }
        self.window = window
    }

    /// Shows the window if needed, then runs `then` once it's on screen.
    func open(_ placement: PanelWindowPlacement, then: @escaping () -> Void) {
        if isVisible {
            then()
            return
        }
        onNextReveal = then
        show(placement)
    }

    /// Runs after the next reveal (see `open(_:then:)`).
    private var onNextReveal: (() -> Void)?

    /// Positions the window — under the status item, or centred on a
    /// screen — then reveals it per `presentationCoordinator`'s
    /// `.preserve`/`.todayNow` behavior.
    func show(_ placement: PanelWindowPlacement) {
        // Its views mount now, while the window is still hidden.
        hostPresentation?.isPresented = true
        switch placement {
        case .anchored(let screenAnchor):
            applyPlacement(anchoredTo: screenAnchor)
        case .centered(let screen):
            let frame = CommandWindowPlacement(size: window.frame.size, minSize: window.minSize,
                                               visibleFrame: screen.visibleFrame).frame
            window.setFrame(frame, display: false)
        }

        let request = presentationCoordinator.willOpen()
        switch request.behavior {
        case .preserve:
            // Nothing to reposition — the root view leaves both scroll
            // views exactly as they were, so there's no scroll-in to hide.
            revealWindow()
        case .todayNow:
            // The window's content view stays mounted/laid out even while
            // `orderOut` — that's what lets the root view's scroll-to-
            // today positioning actually run (and finish) before anyone
            // can see it, instead of revealing first and positioning a
            // visible frame or two later. `markReady` (via `onReady`) is
            // the root view's "I've actually applied it" signal.
            let requestID = request.id
            var didReveal = false
            presentationCoordinator.onReady = { [weak self] readyID in
                guard readyID == requestID, !didReveal else { return }
                didReveal = true
                self?.revealWindow()
            }
            // Safety net: if that signal never arrives for some reason
            // (a future change to the positioning path, a genuinely empty
            // agenda with nothing to scroll to), don't leave the window
            // stuck invisible forever.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard !didReveal else { return }
                didReveal = true
                self?.revealWindow()
            }
        }
    }

    func toggle(_ placement: PanelWindowPlacement) {
        if isVisible {
            hide()
        } else {
            show(placement)
        }
    }

    func reposition(anchoredTo screenAnchor: PopoverAnchor) {
        guard isVisible else { return }
        applyPlacement(anchoredTo: screenAnchor)
    }

    private func applyPlacement(anchoredTo screenAnchor: PopoverAnchor) {
        let placement = PopoverPlacement(
            anchor: screenAnchor,
            windowSize: window.frame.size,
            arrowInset: AppTheme.Metrics.popoverPointerInset
        )
        presentationCoordinator.pointerXOffset = placement.arrowX - window.frame.width / 2
        window.setFrameOrigin(placement.windowOrigin)
    }

    private func revealWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installClickOutsideMonitors()
        hostPresentation?.didReveal()
        let then = onNextReveal
        onNextReveal = nil
        then?()
    }

    func hide() {
        onNextReveal = nil
        guard window.isVisible else { return }
        window.orderOut(nil)
        hostPresentation?.isPresented = false
        presentationCoordinator.didHide()
        removeClickOutsideMonitors()
    }

    /// A borderless window is not a real `NSPopover`, so it has no
    /// built-in "click outside to dismiss" — a global monitor catches
    /// clicks in *other* apps, a local one catches clicks elsewhere in
    /// *this* one (e.g. the Settings window).
    private func installClickOutsideMonitors() {
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return }
            // The first click after the popover opens can reach this
            // "other apps" monitor too (activation is asynchronous, so the
            // window server may still route it as if another app were
            // frontmost) — even though it lands on the popover. Only a click
            // on a window that isn't ours is outside.
            if self.isInside(NSApp.window(withWindowNumber: event.windowNumber), at: NSEvent.mouseLocation) { return }
            self.hide()
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            // A click on the popover itself, or inside any *nested*
            // SwiftUI `.popover` (the event detail card, the
            // weather/switcher tooltips, the calendar picker — each of
            // those is its own child `NSWindow`, not `window` itself)
            // isn't "outside." Without the descendant check, a click on
            // anything inside one of those — e.g. the attendee copy
            // button — read as "outside" and closed the whole app. The
            // anchoring status item is excluded too (`anchorScreenFrame`).
            if self.isInside(event.window, at: NSEvent.mouseLocation) { return event }
            self.hide()
            return event
        }
    }

    /// Set by `AppDelegate` to the status item button's frame on screen. A
    /// click there belongs to the button's own action, never "outside":
    /// closing on its mouse-down made the mouse-up reopen the panel. By
    /// position, so it holds whichever window the click is reported on.
    var anchorScreenFrame: () -> CGRect? = { nil }

    private func isInside(_ candidate: NSWindow?, at point: CGPoint) -> Bool {
        Self.isInside(clickAt: point, onOwnWindow: isOwnWindow(candidate), anchorFrame: anchorScreenFrame())
    }

    static func isInside(clickAt point: CGPoint, onOwnWindow: Bool, anchorFrame: CGRect?) -> Bool {
        onOwnWindow || anchorFrame?.contains(point) == true
    }

    /// The popover or one of its nested popovers.
    private func isOwnWindow(_ candidate: NSWindow?) -> Bool {
        // An app-modal alert of ours is never "outside".
        if let candidate, candidate === NSApp.modalWindow { return true }
        return candidate === window || Self.isWindow(candidate, descendantOf: window)
    }

    /// Up through child windows (popovers, panels) *and* sheets — a
    /// SwiftUI `confirmationDialog` in a popover is a sheet on its window,
    /// linked by `sheetParent`, not `parent`. Missing that made a click on
    /// "This Event Only" read as outside and close the whole panel.
    static func isWindow(_ candidate: NSWindow?, descendantOf ancestor: NSWindow) -> Bool {
        var current = candidate
        while let window = current {
            if window === ancestor { return true }
            current = window.parent ?? window.sheetParent
        }
        return false
    }

    private func removeClickOutsideMonitors() {
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        globalClickMonitor = nil
        localClickMonitor = nil
    }
}

/// Where `PopoverWindowController` puts its window.
enum PanelWindowPlacement {
    /// Under the status item, its pointer at the button.
    case anchored(PopoverAnchor)
    /// Centred on this screen (`CommandWindowPlacement`).
    case centered(NSScreen)
}

/// A panel window's size: where it starts, how far it resizes, and
/// whether the user's size is remembered.
struct PanelWindowSize {
    let size: NSSize
    let minSize: NSSize
    let maxSize: NSSize
    var autosaveName: String?

    /// The menu-bar popover: vertical-only — the width is locked (equal
    /// min/max) so the resize edges only move the bottom edge, growing or
    /// shrinking how much agenda is visible.
    static func popover(pointerHeight: CGFloat) -> PanelWindowSize {
        let width = AppTheme.Metrics.popoverWidth
        return PanelWindowSize(size: NSSize(width: width, height: AppTheme.Metrics.popoverHeight + pointerHeight),
                               minSize: NSSize(width: width, height: 320 + pointerHeight),
                               maxSize: NSSize(width: width, height: 1400 + pointerHeight))
    }

    /// The Command Window: resizable both ways, its size remembered.
    static let commandWindow = PanelWindowSize(
        size: AppTheme.CommandWindow.size,
        minSize: AppTheme.CommandWindow.minSize,
        maxSize: NSSize(width: 2400, height: 1600),
        autosaveName: "CommandWindow"
    )
}
