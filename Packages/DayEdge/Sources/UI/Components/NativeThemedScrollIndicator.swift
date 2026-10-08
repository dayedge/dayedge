import AppKit
import SwiftUI

/// AppKit owns scrolling, knob tracking and fading. Only the parts' appearance
/// and geometry are customized; the transparent track remains interactive.
package final class ThemedNativeScroller: NSScroller {
    package override static var isCompatibleWithOverlayScrollers: Bool { true }
    package override var isOpaque: Bool { false }

    package private(set) var indicatorStyle = ScrollIndicatorStyle.tinyPersistent
    private var ink = NSColor.white.withAlphaComponent(0.35)

    package func apply(style: ScrollIndicatorStyle) {
        guard indicatorStyle != style else { return }
        indicatorStyle = style
        let color = NSColor(style.color)
        ink = color.withAlphaComponent(color.alphaComponent * style.opacity)
        needsDisplay = true
    }

    /// The visible pill and the native drag region have the same vertical
    /// extent. The hit region uses the whole native width, not just four points.
    package override func rect(for part: NSScroller.Part) -> NSRect {
        switch part {
        case .knobSlot:
            return bounds.insetBy(dx: 0, dy: min(indicatorStyle.verticalInset, bounds.height / 2))
        case .knob:
            let pill = pillRect
            return pill.isEmpty ? .zero : NSRect(x: bounds.minX, y: pill.minY, width: bounds.width, height: pill.height)
        default:
            return super.rect(for: part)
        }
    }

    package var pillRect: NSRect {
        Self.pillRect(in: bounds, flipped: isFlipped, value: doubleValue, proportion: knobProportion, style: indicatorStyle)
    }

    package static func pillRect(in bounds: NSRect, flipped: Bool, value: Double, proportion: CGFloat, style: ScrollIndicatorStyle) -> NSRect {
        guard proportion > 0, proportion < 1, bounds.width > 0, bounds.height > 0 else { return .zero }
        let inset = min(max(style.verticalInset, 0), bounds.height / 2)
        let trackHeight = max(bounds.height - inset * 2, 0)
        let maximum = min(style.maximumHeight ?? trackHeight, trackHeight)
        let minimum = min(style.minimumHeight, maximum)
        let height = min(max((trackHeight * proportion).rounded(), minimum), maximum)
        let travel = max(trackHeight - height, 0)
        let progress = CGFloat(min(max(value, 0), 1))
        let y = flipped ? bounds.minY + inset + travel * progress : bounds.maxY - inset - height - travel * progress
        return NSRect(x: bounds.maxX - style.trailingInset - style.width, y: y, width: style.width, height: height)
    }

    package override func drawKnobSlot(in slotRect: NSRect, highlight: Bool) {}

    package override func drawKnob() {
        guard isEnabled, !pillRect.isEmpty else { return }
        NSGraphicsContext.saveGraphicsState()
        if indicatorStyle.shadowRadius > 0 {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(indicatorStyle.shadowColor)
            shadow.shadowBlurRadius = indicatorStyle.shadowRadius
            shadow.shadowOffset = .zero
            shadow.set()
        }
        ink.setFill()
        NSBezierPath(roundedRect: pillRect, xRadius: indicatorStyle.width / 2, yRadius: indicatorStyle.width / 2).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// A view-local bridge into SwiftUI's existing scroll view. It never replaces
/// the document/clip views or publishes per-frame geometry back into SwiftUI.
package struct NativeThemedScrollIndicator: NSViewRepresentable {
    package let style: ScrollIndicatorStyle
    /// The knob is dragged (or the track clicked): true at the start, false
    /// at the end. SwiftUI reports no scroll phase for this.
    package var onTracking: ((Bool) -> Void)?

    package func makeCoordinator() -> Coordinator { Coordinator(style: style) }

    package func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onHierarchyChange = { [weak coordinator = context.coordinator, weak view] in
            coordinator?.scheduleAttachment(of: view)
        }
        context.coordinator.scheduleAttachment(of: view)
        return view
    }

    package func updateNSView(_ nsView: ProbeView, context: Context) {
        context.coordinator.apply(style: style)
        context.coordinator.onTracking = onTracking
    }

    package static func dismantleNSView(_ nsView: ProbeView, coordinator: Coordinator) {
        nsView.onHierarchyChange = nil
        coordinator.dismantle()
    }

    package final class ProbeView: NSView {
        package var onHierarchyChange: (() -> Void)?
        package override var intrinsicContentSize: NSSize { .zero }
        package override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            onHierarchyChange?()
        }
        package override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onHierarchyChange?()
        }
    }

    /// Installs the themed scroller into SwiftUI's own `NSScrollView` and
    /// keeps it there.
    ///
    /// SwiftUI owns that scroll view, so it may put its own scroller (or
    /// style) back; the KVO observers then re-install ours. Today that
    /// happens rarely and one repair settles it. Nothing guarantees it on
    /// a future macOS: if SwiftUI re-applied its scroller on every update,
    /// each repair would provoke the next — an endless swap, re-tiling the
    /// scroll view every turn (CPU, flicker) with nothing to show for it.
    /// So repairs are bounded (`repairLimit` within `repairWindow`); past
    /// that the coordinator gives that scroll view up to SwiftUI for good
    /// (`yieldToSwiftUI`): the system's overlay scroller stays — it works,
    /// it just isn't themed — and scrolling, paging and drag tracking are
    /// unaffected.
    @MainActor
    package final class Coordinator {
        /// Re-installs allowed within `repairWindow` before giving up.
        package static let repairLimit = 5
        package static let repairWindow: TimeInterval = 1

        private var style: ScrollIndicatorStyle
        package var onTracking: ((Bool) -> Void)?
        private var liveScrollObservers: [NSObjectProtocol] = []
        private var isTracking = false
        private weak var scrollView: NSScrollView?
        private weak var probe: ProbeView?
        package private(set) var scroller: ThemedNativeScroller?
        private var previousScroller: NSScroller?
        private var previousStyle: NSScroller.Style = .overlay
        private var previousAutohides = false
        private var previousHasVerticalScroller = false
        private var replacementObservation: NSKeyValueObservation?
        private var styleObservation: NSKeyValueObservation?
        private var attachmentScheduled = false
        private var repairScheduled = false
        private var isDismantled = false
        /// When each re-install happened, within the last `repairWindow`.
        private var repairTimes: [TimeInterval] = []
        /// Repairs ran out for this scroll view: SwiftUI's scroller stays.
        package private(set) var hasYieldedToSwiftUI = false
        private let now: () -> TimeInterval

        package init(style: ScrollIndicatorStyle, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
            self.style = style
            self.now = now
        }

        package func apply(style: ScrollIndicatorStyle) {
            guard self.style != style else { return }
            self.style = style
            scroller?.apply(style: style)
        }

        package func scheduleAttachment(of probe: ProbeView?) {
            guard !isDismantled else { return }
            self.probe = probe
            guard !attachmentScheduled else { return }
            attachmentScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isDismantled else { return }
                self.attachmentScheduled = false
                self.attach(to: self.probe?.enclosingScrollView)
            }
        }

        package func attach(to scrollView: NSScrollView?) {
            guard !isDismantled, self.scrollView !== scrollView else { return }
            detach()
            guard let scrollView else { return }
            self.scrollView = scrollView
            // A new scroll view gets its own budget.
            repairTimes = []
            hasYieldedToSwiftUI = false
            previousScroller = scrollView.verticalScroller
            previousStyle = scrollView.scrollerStyle
            previousAutohides = scrollView.autohidesScrollers
            previousHasVerticalScroller = scrollView.hasVerticalScroller
            let scroller = ThemedNativeScroller()
            scroller.apply(style: style)
            self.scroller = scroller
            install()
            replacementObservation = scrollView.observe(\.verticalScroller, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.scheduleRepair() }
            }
            styleObservation = scrollView.observe(\.scrollerStyle, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.scheduleRepair() }
            }
            // Live scrolls include dragging the scroller; a gesture is
            // reported by SwiftUI already, so only scroller tracking counts.
            liveScrollObservers = [
                NotificationCenter.default.addObserver(forName: NSScrollView.willStartLiveScrollNotification, object: scrollView,
                                                       queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.liveScrollStarted() }
                },
                NotificationCenter.default.addObserver(forName: NSScrollView.didEndLiveScrollNotification, object: scrollView,
                                                       queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.setTracking(false) }
                }
            ]
        }

        private func liveScrollStarted() {
            // Whichever scroller is installed — ours, or SwiftUI's after
            // `yieldToSwiftUI` — dragging it is the reader scrolling.
            guard let scroller = scrollView?.verticalScroller, NSEvent.pressedMouseButtons & 1 == 1,
                  let window = scroller.window else { return }
            let point = scroller.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            guard scroller.bounds.contains(point) else { return }
            setTracking(true)
        }

        package func setTracking(_ tracking: Bool) {
            guard tracking != isTracking else { return }
            isTracking = tracking
            onTracking?(tracking)
        }

        private func install() {
            guard let scrollView, let scroller else { return }
            scrollView.hasVerticalScroller = true
            scrollView.autohidesScrollers = true
            if scrollView.verticalScroller !== scroller {
                scrollView.verticalScroller = scroller
            }
            if scrollView.scrollerStyle != .overlay { scrollView.scrollerStyle = .overlay }
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func scheduleRepair() {
            guard !isDismantled, !repairScheduled else { return }
            repairScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isDismantled else { return }
                self.repairScheduled = false
                guard let scrollView = self.scrollView, let scroller = self.scroller else { return }
                if let replacement = scrollView.verticalScroller, replacement !== scroller {
                    self.previousScroller = replacement
                }
                guard scrollView.verticalScroller !== scroller || scrollView.scrollerStyle != .overlay else { return }
                guard self.recordRepair() else {
                    self.yieldToSwiftUI()
                    return
                }
                self.install()
            }
        }

        /// Counts a re-install; false once the window's budget is spent.
        private func recordRepair() -> Bool {
            let time = now()
            repairTimes = repairTimes.filter { time - $0 < Self.repairWindow } + [time]
            return repairTimes.count <= Self.repairLimit
        }

        /// Stops fighting SwiftUI over this scroll view: no more observing
        /// or re-installing, and its own scroller (already back in place)
        /// stays. Drag tracking keeps working — it watches the scroll view.
        private func yieldToSwiftUI() {
            hasYieldedToSwiftUI = true
            replacementObservation?.invalidate()
            styleObservation?.invalidate()
            replacementObservation = nil
            styleObservation = nil
            scroller = nil
        }

        package func dismantle() {
            isDismantled = true
            probe = nil
            detach()
        }

        private func detach() {
            liveScrollObservers.forEach { NotificationCenter.default.removeObserver($0) }
            liveScrollObservers = []
            setTracking(false)
            replacementObservation?.invalidate()
            styleObservation?.invalidate()
            replacementObservation = nil
            styleObservation = nil
            if let scrollView, let scroller, scrollView.verticalScroller === scroller {
                scrollView.verticalScroller = previousScroller
                scrollView.scrollerStyle = previousStyle
                scrollView.autohidesScrollers = previousAutohides
                scrollView.hasVerticalScroller = previousHasVerticalScroller
            }
            scrollView = nil
            scroller = nil
            previousScroller = nil
        }
    }
}
