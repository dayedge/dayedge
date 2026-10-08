import AppKit
import SwiftUI
import UI

private final class MeetingTakeoverWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// One logical takeover, rendered by one window per selected physical display.
/// The windows share a single observable state and a single clock.
@MainActor
final class FullScreenMeetingTakeoverPresenter: MeetingHUDPresenting {
    private struct Presentation {
        let display: MeetingHUDDisplay
        let onJoin: () -> Void
        let onSnoozeSmart: () -> Void
        let onSnoozeDuration: (TimeInterval) -> Void
        let onDismiss: () -> Void
    }

    private var windows: [CGDirectDisplayID: MeetingTakeoverWindow] = [:]
    private var state: MeetingTakeoverState?
    private var presentation: Presentation?
    private var clockTimer: Timer?
    private var pointerTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var keyMonitor: Any?
    private var pointerMigration = MeetingTakeoverPointerMigration()
    private var pointerLocationAtScreenChange: NSPoint?
    private var previousFrontmostApp: NSRunningApplication?
    private var dismissalGeneration = UUID()

    func show(_ occurrence: MeetingHUDOccurrence, display: MeetingHUDDisplay, actions: MeetingHUDActions) {
        dismissalGeneration = UUID()
        let firstAppearance = state == nil
        presentation = Presentation(
            display: display, onJoin: actions.join, onSnoozeSmart: actions.snoozeSmart,
            onSnoozeDuration: actions.snoozeDuration, onDismiss: actions.dismiss
        )
        let selected = MeetingHUDDisplaySelection.screens(for: display)
        let initialID = (display == .all
            ? MeetingHUDDisplaySelection.screens(for: .active).first?.stableDisplayID
            : selected.first?.stableDisplayID) ?? selected.first?.stableDisplayID
        guard let initialID else { hide(); return }

        if let state {
            state.occurrence = occurrence
            state.now = .now
        } else {
            previousFrontmostApp = NSWorkspace.shared.frontmostApplication
            state = MeetingTakeoverState(occurrence: occurrence, now: .now, activeDisplayID: initialID)
        }
        reconcileWindows()

        if firstAppearance {
            startObserving()
            NSApp.activate(ignoringOtherApps: true)
            windows[state!.activeDisplayID]?.makeKeyAndOrderFront(nil)
        }
    }

    private func reconcileWindows() {
        guard let state, let presentation else { return }
        pointerMigration = MeetingTakeoverPointerMigration()
        let selected = MeetingHUDDisplaySelection.screens(for: presentation.display)
        let selectedIDs = Set(selected.compactMap(\.stableDisplayID))

        for id in windows.keys where !selectedIDs.contains(id) {
            windows[id]?.orderOut(nil)
            windows[id] = nil
        }

        var appearing: [MeetingTakeoverWindow] = []
        for screen in selected {
            guard let id = screen.stableDisplayID else { continue }
            let isNew = windows[id] == nil
            let window = windows[id] ?? makeWindow(for: screen, id: id, state: state)
            windows[id] = window
            // Geometry and hosting layout must settle while invisible.
            // Animating only opacity avoids the top-left "window growing"
            // artifact of revealing an unlaid-out fullscreen window.
            window.setFrame(screen.frame, display: true)
            window.contentView?.layoutSubtreeIfNeeded()
            if isNew { appearing.append(window) }
        }
        for screen in selected {
            guard let id = screen.stableDisplayID, let window = windows[id] else { continue }
            window.orderFrontRegardless()
        }
        if !appearing.isEmpty {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                appearing.forEach { $0.animator().alphaValue = 1 }
            }
        }

        if !selectedIDs.contains(state.activeDisplayID) {
            state.activeDisplayID = MeetingHUDDisplaySelection.screens(for: .active)
                .first(where: { screen in
                    screen.stableDisplayID.map(selectedIDs.contains) ?? false
                })?.stableDisplayID
                ?? selected.first?.stableDisplayID
                ?? state.activeDisplayID
        }
        if presentation.display != .all,
           let onlyID = selected.first?.stableDisplayID {
            state.activeDisplayID = onlyID
        }
    }

    private func makeWindow(
        for screen: NSScreen, id: CGDirectDisplayID, state: MeetingTakeoverState
    ) -> MeetingTakeoverWindow {
        let window = MeetingTakeoverWindow(
            contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.alphaValue = 0
        // Above ordinary/full-screen apps, but below native popovers and
        // system alerts. `.screenSaver` would cover our own Event Details.
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: TakeoverThemedRoot(content: MeetingTakeoverView(
            state: state, displayID: id,
            onJoin: { [weak self] in self?.presentation?.onJoin() },
            onSnoozeSmart: { [weak self] in self?.presentation?.onSnoozeSmart() },
            onSnoozeDuration: { [weak self] duration in self?.presentation?.onSnoozeDuration(duration) },
            onDismiss: { [weak self] in self?.presentation?.onDismiss() }
        )))
        return window
    }

    private func startObserving() {
        let clock = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.state?.now = .now }
        }
        RunLoop.main.add(clock, forMode: .common)
        clockTimer = clock

        let pointer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.samplePointer() }
        }
        RunLoop.main.add(pointer, forMode: .common)
        pointerTimer = pointer

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pointerLocationAtScreenChange = NSEvent.mouseLocation
                self?.reconcileWindows()
            }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event)
        }
    }

    /// The takeover's keys: S (Shift-S) reminds, Return joins (or opens the
    /// event details when focused), Esc dismisses.
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard self.presentation != nil,
              let eventWindow = event.window ?? NSApp.keyWindow,
              self.windows.values.contains(where: { $0 === eventWindow }),
              event.modifierFlags.isDisjoint(with: [.command, .control, .option])
        else { return event }
        // A native popover owns Return/Escape while editing its duration;
        // neither key may Join or Dismiss the underlying takeover.
        if self.state?.isCustomSnoozePresented == true { return event }
        switch event.keyCode {
        case 1: // S: default reminder; Shift-S: custom reminder.
            if event.modifierFlags.contains(.shift) {
                self.state?.customReminderRequest = UUID()
            } else {
                self.presentation?.onSnoozeSmart()
            }
            return nil
        case 36, 76:
            if self.state?.isEventHeaderFocused == true {
                self.state?.detailToggleRequest = UUID()
                return nil
            }
            if self.state?.occurrence.meetingURL != nil {
                self.presentation?.onJoin()
                return nil
            }
            return event
        case 53:
            self.presentation?.onDismiss()
            return nil
        default:
            return event
        }
    }

    private func samplePointer() {
        guard let presentation, presentation.display == .all, let state else { return }
        let pointer = NSEvent.mouseLocation
        if let origin = pointerLocationAtScreenChange {
            guard hypot(pointer.x - origin.x, pointer.y - origin.y) > 2 else { return }
            pointerLocationAtScreenChange = nil
        }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }),
              let id = screen.stableDisplayID, windows[id] != nil else {
            pointerMigration = MeetingTakeoverPointerMigration()
            return
        }

        if let nextID = pointerMigration.nextActiveDisplayID(
            currentID: state.activeDisplayID,
            pointerID: id,
            isClearlyInside: screen.frame.insetBy(dx: 12, dy: 12).contains(pointer),
            now: .now
        ) {
            withAnimation(.easeInOut(duration: 0.18)) {
                state.activeDisplayID = nextID
            }
            // The interactive controls moved too; keep Tab/Shift-Tab on
            // their window rather than leaving keyboard focus on a passive
            // display's overlay.
            windows[nextID]?.makeKeyAndOrderFront(nil)
        }
    }

    func hide() { hide(restoreFocus: true) }

    func hide(restoreFocus: Bool) {
        guard let state else { return }
        let retiringWindows = Array(windows.values)
        let generation = UUID()
        dismissalGeneration = generation
        withAnimation(.easeIn(duration: 0.16)) { state.isExiting = true }
        clockTimer?.invalidate()
        pointerTimer?.invalidate()
        clockTimer = nil
        pointerTimer = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        windows.removeAll()
        self.state = nil
        presentation = nil
        pointerMigration = MeetingTakeoverPointerMigration()
        pointerLocationAtScreenChange = nil
        let appToRestore = restoreFocus && NSApp.isActive ? previousFrontmostApp : nil
        previousFrontmostApp = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.19
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            retiringWindows.forEach { $0.animator().alphaValue = 0 }
        } completionHandler: { [weak self] in
            Task { @MainActor in
                retiringWindows.forEach { $0.orderOut(nil) }
                guard self?.dismissalGeneration == generation,
                      let appToRestore,
                      appToRestore.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
                appToRestore.activate(options: [])
            }
        }
    }
}

/// The takeover's theme: the app's, or — for the Graphite and Frosted
/// Glass backgrounds — Opal's, following the setting live.
private struct TakeoverThemedRoot<Content: View>: View {
    let content: Content
    @AppStorage(MeetingHUDSettings.takeoverBackdropKey) private var backdrop = TakeoverBackdropChoice.theme.rawValue

    var body: some View {
        ThemedRoot(content: content,
                   fixedTheme: (TakeoverBackdropChoice(rawValue: backdrop) ?? .theme).fixedTheme)
    }
}
