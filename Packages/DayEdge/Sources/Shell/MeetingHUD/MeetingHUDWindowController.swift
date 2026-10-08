import AppKit
import SwiftUI
import UI

/// No `canBecomeKey`/`canBecomeMain` override, deliberately — see
/// `MeetingHUDWindowController.makePanel`'s doc comment for why.
final class MeetingHUDPanel: NSPanel {}

/// Owns the Meeting HUD's floating panel — a single, reused
/// `MeetingHUDPanel`, positioned bottom-center on the configured
/// display, shown/hidden with a restrained fade (+ small vertical move
/// on show), and content-swappable in place so `MeetingHUDController`
/// can update an already-visible occurrence without tearing the window
/// down and rebuilding it.
@MainActor
final class MeetingHUDWindowController {
    let fixedDisplayID: CGDirectDisplayID?
    var panel: MeetingHUDPanel?
    private let interactionState = CompactMeetingHUDInteractionState()
    private var keyMonitor: Any?
    private var keyboardActions: MeetingHUDActions?
    private var hasJoinURL = false
    /// Guards against an animation-completion race: if `hide()`'s fade
    /// finishes *after* a newer `show()` has already re-shown the panel,
    /// the stale completion must not order the panel back out from under
    /// the newer content.
    private var presentationGeneration = UUID()

    var screenChangeObserver: NSObjectProtocol?
    /// Dragging is calculated entirely in AppKit screen coordinates. A
    /// SwiftUI-local translation is not stable here: moving the panel also
    /// moves the coordinate space the gesture is measured in, producing a
    /// feedback loop and visibly jerky motion.
    var dragStartOrigin: NSPoint?
    var dragStartMouseLocation: NSPoint?
    var dragRawOrigin: NSPoint?
    var dragTargetScreen: NSScreen?
    var isDragging = false
    var pendingRootViewWhileDragging: MeetingHUDView?
    let magnetism = MeetingHUDMagnetism()

    init(fixedDisplayID: CGDirectDisplayID? = nil) {
        self.fixedDisplayID = fixedDisplayID
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let screenChangeObserver { NotificationCenter.default.removeObserver(screenChangeObserver) }
    }

    func show(_ occurrence: MeetingHUDOccurrence, display: MeetingHUDDisplay, actions: MeetingHUDActions) {
        presentationGeneration = UUID()
        keyboardActions = actions
        hasJoinURL = occurrence.meetingURL != nil
        let rootView = MeetingHUDView(
            occurrence: occurrence, interactionState: interactionState,
            onJoin: actions.join, onSnoozeSmart: actions.snoozeSmart,
            onSnoozeDuration: actions.snoozeDuration,
            onResetPosition: { [weak self] in self?.resetPosition() },
            onDismiss: actions.dismiss,
            onDragChanged: { [weak self] in self?.handleDragChanged() },
            onDragEnded: { [weak self] in self?.handleDragEnded() }
        )

        if let panel, panel.isVisible {
            // Already on screen — an idempotent content/position update
            // only, deliberately with no reveal animation (an occurrence
            // already showing shouldn't re-play the arrival animation on
            // every minor content refresh).
            if isDragging {
                // Replacing the SwiftUI root while its drag gesture is active
                // can cancel that gesture before `onEnded` and strand the
                // controller in dragging state. Apply content changes once
                // direct manipulation has deterministically finished.
                pendingRootViewWhileDragging = rootView
            } else {
                (panel.contentViewController as? NSHostingController<ThemedRoot<MeetingHUDView>>)?.rootView = ThemedRoot(content: rootView)
                position(panel, on: screen(for: display))
            }
            reveal(panel)
            return
        }

        // Either genuinely first-time, or the existing panel was hidden
        // (`hide()` fades `alphaValue` to 0 and orders it out, and never
        // resets `alphaValue` back — reusing it here without the same
        // "start invisible, reveal" treatment below would bring a
        // frontmost but fully transparent window, i.e. "nothing shows").
        let panel = self.panel ?? makePanel(rootView: rootView)
        self.panel = panel
        (panel.contentViewController as? NSHostingController<ThemedRoot<MeetingHUDView>>)?.rootView = ThemedRoot(content: rootView)
        position(panel, on: screen(for: display))
        panel.alphaValue = 0
        reveal(panel)

        // Keep the real window frame at its resting position. Moving the
        // NSPanel itself during reveal makes an immediate user drag fight an
        // outstanding frame animation. The same visual travel/scale happens
        // entirely on the content layer instead.
        var revealStartTransform = CATransform3DMakeScale(Self.revealStartScale, Self.revealStartScale, 1)
        revealStartTransform = CATransform3DTranslate(revealStartTransform, 0, -Self.revealTravel, 0)
        panel.contentView?.layer?.transform = revealStartTransform

        let scaleAnimation = CABasicAnimation(keyPath: "transform")
        scaleAnimation.fromValue = revealStartTransform
        scaleAnimation.toValue = CATransform3DIdentity
        scaleAnimation.duration = Self.revealDuration
        // Plain ease-out, deliberately not a spring — guarantees no
        // overshoot above scale 1.0 rather than merely tuning damping
        // to make one unlikely.
        scaleAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        panel.contentView?.layer?.transform = CATransform3DIdentity
        panel.contentView?.layer?.add(scaleAnimation, forKey: "revealTransform")

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.revealDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        interactionState.hasFocusedControl = false
        interactionState.isCustomReminderPresented = false
        cancelActiveDrag()
        let generation = presentationGeneration
        // Much quieter than the reveal — a small downward settle, no
        // scale change, no separate border/color animation.
        let dismissFrame = panel.frame.offsetBy(dx: 0, dy: -Self.dismissTravel)
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = Self.dismissDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
                panel.animator().setFrame(dismissFrame, display: true)
            },
            completionHandler: { [weak self] in
                Task { @MainActor in
                    guard let self, self.presentationGeneration == generation else { return }
                    panel.orderOut(nil)
                }
            }
        )
    }

    private static let revealTravel: CGFloat = 20
    private static let revealStartScale: CGFloat = 0.97
    private static let revealDuration: CFTimeInterval = 0.24
    private static let dismissTravel: CGFloat = 6
    private static let dismissDuration: CFTimeInterval = 0.14

    private func makePanel(rootView: MeetingHUDView) -> MeetingHUDPanel {
        let hosting = NSHostingController(rootView: ThemedRoot(content: rootView))
        let panel = MeetingHUDPanel(contentViewController: hosting)
        panel.styleMask = [.nonactivatingPanel, .borderless]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The shared the app surface draws the compact window's one
        // restrained shadow; a native window shadow would double it.
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Unlike `NSWindow`, `NSPanel` defaults `hidesOnDeactivate` to
        // `true` — it would auto-hide the instant the app itself stops
        // being the active app, i.e. the moment the user clicks into any
        // other application. The HUD must stay up until Join/Snooze/
        // Dismiss regardless of which app is currently active.
        panel.hidesOnDeactivate = false
        // The standard AppKit pattern for "floating panel with
        // interactive controls that must not steal focus on
        // appearance": never becomes key when merely shown (see
        // `reveal`, which uses `orderFrontRegardless`, never
        // `makeKeyAndOrderFront`/`NSApp.activate`), but *can* become key
        // if the user actually clicks into it — needed for the Snooze
        // menu's `NSMenu` tracking to behave reliably. Overriding
        // `canBecomeKey` to `false` outright (a stronger constraint) can
        // make that interaction unreliable.
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        installKeyboardMonitor()
        // Direct manipulation is handled explicitly via `MeetingHUDView`'s
        // own `DragGesture` (see `handleDragChanged`/`handleDragEnded`)
        // rather than `NSWindow.isMovableByWindowBackground` — the whole
        // HUD is one single SwiftUI-hosted `NSView`, so AppKit has no way
        // to tell "over Join" from "over the title text" at the `NSView`
        // level, and setting that flag either dragged from everywhere
        // (swallowing every button's clicks) or nowhere.
        observeScreenChanges(panel)
        return panel
    }

    private func installKeyboardMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, panel.isVisible,
                  event.window === panel,
                  !self.interactionState.isCustomReminderPresented,
                  event.modifierFlags.isDisjoint(with: [.command, .control, .option])
            else { return event }
            switch event.keyCode {
            case 1: // S, or Shift-S for a custom reminder.
                if event.modifierFlags.contains(.shift) {
                    self.interactionState.customReminderRequest = UUID()
                } else {
                    self.keyboardActions?.snoozeSmart()
                }
                return nil
            case 36, 76:
                if self.interactionState.hasFocusedControl { return event }
                guard self.hasJoinURL else { return event }
                self.keyboardActions?.join()
                return nil
            case 53:
                self.keyboardActions?.dismiss()
                return nil
            default:
                return event
            }
        }
    }

    private func reveal(_ panel: NSPanel) {
        panel.orderFrontRegardless()
    }
}
