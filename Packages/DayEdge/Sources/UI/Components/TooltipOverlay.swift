import SwiftUI

import AppKit

/// Tooltips are a tiny click-through panel — like native macOS tooltips —
/// never an `NSPopover`: a transient popover swallows the next click to
/// dismiss itself, which made controls need two clicks. The panel ignores
/// the mouse, never becomes key, and hides the instant a mouse button goes
/// down, so the click always reaches the control underneath.
///
/// It is anchored to the trigger's real on-screen frame (via an AppKit view
/// in the trigger's background), which works even for pinned section
/// headers where SwiftUI's anchor preferences don't resolve.
private struct TooltipModifier<TooltipContent: View>: ViewModifier {
    let isPresented: Bool
    let edge: Edge
    let delay: Duration
    let tooltipContent: () -> TooltipContent

    @State private var controller = TooltipPanelController()

    func body(content: Content) -> some View {
        content
            .background(TooltipAnchorView(controller: controller))
            .onChange(of: isPresented) { _, presented in update(presented) }
            // `.onChange` never fires for the initial value — a trigger
            // that's already hovered at mount time still needs scheduling.
            .onAppear { update(isPresented) }
            .onDisappear { controller.hide() }
    }

    private func update(_ presented: Bool) {
        if presented {
            controller.schedule(after: delay, edge: edge, content: AnyView(tooltipContent()))
        } else {
            controller.hide()
            controller.resetSuppression()
        }
    }
}

/// Reports the trigger's AppKit view to its controller, so the panel can
/// be placed against the trigger's real screen frame and parented to its
/// window.
private struct TooltipAnchorView: NSViewRepresentable {
    let controller: TooltipPanelController

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        controller.anchorView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        controller.anchorView = nsView
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {}
}

/// Shared "a tooltip was just visible" moment: sliding from one trigger to
/// the next shows the next hint right away, like the Dock.
@MainActor
private enum TooltipWarmth {
    static var lastHiddenAt: Date = .distantPast
    static let window: TimeInterval = 0.6
    static var isWarm: Bool { Date().timeIntervalSince(lastHiddenAt) < window }
}

@MainActor
package final class TooltipPanelController {
    package weak var anchorView: NSView?

    private var panel: NSPanel?
    private var hosting: NSHostingView<AnyView>?
    private var showTask: Task<Void, Never>?
    private var mouseMonitor: Any?
    /// A click hides the hint until the pointer leaves and comes back.
    private var isSuppressed = false
    /// Guards against a superseded delayed show firing late.
    private var generation = UUID()

    package func schedule(after delay: Duration, edge: Edge, content: AnyView) {
        guard !isSuppressed else { return }
        let token = UUID()
        generation = token
        showTask?.cancel()
        installMouseMonitor()
        let wait = TooltipWarmth.isWarm ? Duration.zero : delay
        showTask = Task { @MainActor [weak self] in
            if wait > .zero {
                try? await Task.sleep(for: wait)
            }
            guard let self, !Task.isCancelled, self.generation == token, !self.isSuppressed else { return }
            self.show(edge: edge, content: content)
        }
    }

    package func hide() {
        generation = UUID()
        showTask?.cancel()
        showTask = nil
        removeMouseMonitor()
        guard let panel, panel.isVisible else { return }
        TooltipWarmth.lastHiddenAt = Date()
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    package func resetSuppression() { isSuppressed = false }

    private func show(edge: Edge, content: AnyView) {
        guard let anchorView, let window = anchorView.window, window.isVisible else { return }
        let panel = self.panel ?? Self.makePanel()
        self.panel = panel

        let surface = AnyView(ThemedRoot(content: TooltipSurface { content }))
        if let hosting {
            hosting.rootView = surface
        } else {
            let view = NSHostingView(rootView: surface)
            panel.contentView = view
            hosting = view
        }
        guard let hosting else { return }
        let size = hosting.fittingSize

        let anchor = window.convertToScreen(anchorView.convert(anchorView.bounds, to: nil))
        let screen = (window.screen ?? NSScreen.main)?.visibleFrame ?? anchor.insetBy(dx: -2000, dy: -2000)
        let placement = TooltipPlacement.frame(for: size, anchor: anchor, edge: edge, screen: screen)

        panel.setFrame(placement.frame, display: true)
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
        panel.alphaValue = 0
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    /// Any mouse-down hides the hint (and keeps it hidden until the pointer
    /// re-enters). The event is always passed on — never consumed.
    private func installMouseMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.isSuppressed = true
            self?.hide()
            return event
        }
    }

    private func removeMouseMonitor() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
    }

    private static func makePanel() -> NSPanel {
        let panel = TooltipPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // the SwiftUI surface draws its own
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        return panel
    }
}

/// Never key or main: a tooltip can't take focus from a text field.
private final class TooltipPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The tooltip chrome the popover used to provide: a rounded themed card with
/// a hairline edge and a soft shadow (inset so the shadow isn't clipped).
private struct TooltipSurface<Content: View>: View {
    @Environment(\.themePalette) private var theme

    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .themedSurface(.elevated, fill: theme.background, in: Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(theme.secondaryControl.border, lineWidth: 0.5)
            )
            .shadow(color: theme.chrome.tooltipShadow, radius: 6, y: 2)
            .padding(8)
            .fixedSize()
    }
}

extension View {
    /// While `isPresented` is true, `content` is shown near `self` in a
    /// small native popover (after a short hover delay, but hidden the
    /// instant `isPresented` goes false), preferring `edge`.
    package func hoverTooltip<TooltipContent: View>(
        isPresented: Bool,
        edge: Edge = .top,
        delay: Duration = .milliseconds(500),
        @ViewBuilder content: @escaping () -> TooltipContent
    ) -> some View {
        modifier(TooltipModifier(isPresented: isPresented, edge: edge, delay: delay, tooltipContent: content))
    }

    /// Short text hints use the same popover and label as the calendar's
    /// view-mode switcher, without each control owning hover bookkeeping.
    package func hoverTooltip(
        _ text: String,
        shortcut: String? = nil,
        edge: Edge = .top,
        delay: Duration = .milliseconds(500)
    ) -> some View {
        modifier(TextTooltipModifier(text: text, shortcut: shortcut, edge: edge, delay: delay))
    }
}

private struct TextTooltipModifier: ViewModifier {
    let text: String
    let shortcut: String?
    let edge: Edge
    let delay: Duration
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovered = $0 }
            .hoverTooltip(isPresented: isHovered, edge: edge, delay: delay) {
                TooltipLabel(text: text, shortcut: shortcut)
            }
    }
}

/// The simple single-line "label (+ shortcut)" tooltip. The panel's
/// `TooltipSurface` draws the card around it.
package struct TooltipLabel: View {
    @Environment(\.themePalette) private var theme

    package let text: String
    package var shortcut: String?

    package var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(theme.primaryText)

            if let shortcut {
                Text(shortcut)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, 5)
                    .frame(minHeight: 18)
                    .background(
                        theme.secondaryControl.hover,
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(theme.secondaryControl.border, lineWidth: 0.5)
                    }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 11)
        .frame(height: 29)
    }

    package init(text: String, shortcut: String? = nil) {
        self.text = text
        self.shortcut = shortcut
    }
}
