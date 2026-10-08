import AppKit
import SwiftUI

/// View-local native anchors: row identities and their actual clip-relative
/// offsets, including a partially visible first row. No geometry is published
/// into SwiftUI on each scroll tick, and probes are weak and dismantled with rows.
@MainActor
final class ChatTranscriptScrollAnchors {
    struct Snapshot {
        let id: String
        let position: Int
        let offset: CGFloat
        let visibleIDs: [String]
    }

    private struct Probe {
        weak var view: NSView?
        let position: Int
    }

    private struct VisibleRow {
        let id: String
        let position: Int
        let offset: CGFloat
    }

    private var probes: [String: Probe] = [:]
    private var generation = 0
    private var inputMonitor: Any?
    private(set) var snapshot: Snapshot?
    private(set) var isAtTop = true
    private(set) var isRestoring = false

    var probeCount: Int { probes.count }
    var hasInputMonitor: Bool { inputMonitor != nil }

    deinit {
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
    }

    func attach(_ view: NSView, id: String, position: Int) {
        probes[id] = Probe(view: view, position: position)
    }

    func detach(_ view: NSView, id: String) {
        if probes[id]?.view === view { probes[id] = nil }
        if probes.isEmpty { cancelRestoration() }
    }

    func observe(offset: CGFloat) {
        guard !isRestoring else { return }
        isAtTop = offset <= 2
        rememberVisible()
    }

    func rememberVisible() {
        guard !isRestoring else { return }
        snapshot = capture()
    }

    func capture() -> Snapshot? {
        let visible = probes.compactMap { id, probe -> VisibleRow? in
            guard let view = probe.view, let scroll = view.enclosingScrollView,
                  view.window != nil || scroll.superview != nil else { return nil }
            let clip = scroll.contentView
            let frame = view.convert(view.bounds, to: clip)
            guard frame.height > 0, frame.intersects(clip.bounds) else { return nil }
            return VisibleRow(id: id, position: probe.position, offset: Self.offset(of: frame, in: clip))
        }.sorted { $0.offset < $1.offset }
        guard let first = visible.first else { return nil }
        return Snapshot(id: first.id, position: first.position, offset: first.offset, visibleIDs: visible.map(\.id))
    }

    /// A row's distance from the top of what's shown, whichever way the clip view is flipped.
    private static func offset(of frame: CGRect, in clip: NSClipView) -> CGFloat {
        clip.isFlipped ? frame.minY - clip.bounds.minY : clip.bounds.maxY - frame.maxY
    }

    /// Layout the native document before measuring the retained anchor, then
    /// compensate the measured difference. A few bounded deferred passes also
    /// cover SwiftUI's lazy-stack estimate settling after a large window trim.
    func restore(_ anchor: Snapshot) {
        removeInputMonitor()
        generation += 1
        let request = generation
        isRestoring = true
        monitorInput(for: anchor)
        Task { @MainActor [weak self] in
            for _ in 0..<3 {
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }
                guard let self, self.generation == request else { return }
                self.restoreAfterLayout(anchor)
            }
            guard let self, self.generation == request else { return }
            self.isRestoring = false
            self.removeInputMonitor()
            self.snapshot = self.capture()
        }
    }

    /// Lays out, then scrolls by however far the anchor moved. False when
    /// its row isn't there.
    @discardableResult
    func restoreAfterLayout(_ anchor: Snapshot) -> Bool {
        guard let view = probes[anchor.id]?.view, let scroll = view.enclosingScrollView else { return false }
        scroll.layoutSubtreeIfNeeded()
        scroll.documentView?.layoutSubtreeIfNeeded()
        let clip = scroll.contentView
        let correction = (Self.offset(of: view.convert(view.bounds, to: clip), in: clip) - anchor.offset) * (clip.isFlipped ? 1 : -1)
        guard abs(correction) > 0.25 else { return true }
        var origin = clip.bounds.origin
        origin.y += correction
        clip.scroll(to: origin)
        scroll.reflectScrolledClipView(clip)
        return true
    }

    func resetToTop() {
        cancelRestoration()
        isAtTop = true
        snapshot = nil
    }

    func cancelRestoration() {
        generation += 1
        isRestoring = false
        removeInputMonitor()
    }

    /// Input, including momentum wheel events while a gesture is already in
    /// progress, supersedes restoration. Never replay an old viewport offset
    /// over the reader's newer movement.
    func userScrolled() {
        cancelRestoration()
        snapshot = capture()
    }

    private func monitorInput(for anchor: Snapshot) {
        guard let scroll = probes[anchor.id]?.view?.enclosingScrollView, let window = scroll.window else { return }
        inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .leftMouseDragged]) { [weak self, weak scroll, weak window] event in
            guard let scroll, let window, event.window === window,
                  scroll.bounds.contains(scroll.convert(event.locationInWindow, from: nil)) else { return event }
            self?.userScrolled()
            return event
        }
    }

    private func removeInputMonitor() {
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
        inputMonitor = nil
    }
}

struct ChatTranscriptRowAnchorProbe: NSViewRepresentable {
    let id: String
    let position: Int
    let anchors: ChatTranscriptScrollAnchors

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.setAccessibilityElement(false)
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: ProbeView, context: Context) {
        if view.rowID != id { view.anchors?.detach(view, id: view.rowID) }
        view.rowID = id
        view.anchors = anchors
        anchors.attach(view, id: id, position: position)
    }

    static func dismantleNSView(_ view: ProbeView, coordinator: Void) {
        view.anchors?.detach(view, id: view.rowID)
        view.anchors = nil
    }

    final class ProbeView: NSView {
        var rowID = ""
        weak var anchors: ChatTranscriptScrollAnchors?
        override var intrinsicContentSize: NSSize { .zero }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
