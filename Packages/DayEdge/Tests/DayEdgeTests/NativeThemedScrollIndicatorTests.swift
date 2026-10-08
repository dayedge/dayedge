import AppKit
import SwiftUI
import XCTest
@testable import Shell
@testable import UI

@MainActor
final class NativeThemedScrollIndicatorTests: XCTestCase {
    func testPillMatchesInsetsAndMinimumHeightAtBothEnds() {
        let bounds = NSRect(x: 0, y: 0, width: 15, height: 300)
        let style = ScrollIndicatorStyle.tinyPersistent
        let top = ThemedNativeScroller.pillRect(in: bounds, flipped: true, value: 0, proportion: 0.01, style: style)
        let bottom = ThemedNativeScroller.pillRect(in: bounds, flipped: true, value: 1, proportion: 0.01, style: style)
        XCTAssertEqual(top.width, 4)
        XCTAssertEqual(top.height, 28)
        XCTAssertEqual(top.minY, 3)
        XCTAssertEqual(bottom.maxY, 297)
        XCTAssertEqual(top.maxX, bounds.maxX - 3)
        let unflipped = ThemedNativeScroller.pillRect(in: bounds, flipped: false, value: 0, proportion: 0.01, style: style)
        XCTAssertEqual(unflipped, bottom)
    }

    func testProportionalPillClampsToSmallViewportAndMaximum() {
        var style = ScrollIndicatorStyle.tinyPersistent
        let bounds = NSRect(x: 0, y: 0, width: 15, height: 300)
        let proportional = ThemedNativeScroller.pillRect(in: bounds, flipped: true, value: 0.5, proportion: 0.5, style: style)
        XCTAssertEqual(proportional.height, 147)
        XCTAssertEqual(proportional.midY, bounds.midY)
        style.maximumHeight = 60
        XCTAssertEqual(ThemedNativeScroller.pillRect(in: bounds, flipped: true, value: 0.5, proportion: 0.5, style: style).height, 60)
        let smallBounds = NSRect(x: 0, y: 0, width: 15, height: 20)
        XCTAssertEqual(ThemedNativeScroller.pillRect(in: smallBounds, flipped: true, value: 0.5, proportion: 0.01, style: style).height, 14)
        XCTAssertTrue(ThemedNativeScroller.pillRect(in: bounds, flipped: true, value: 0, proportion: 1, style: style).isEmpty)
    }

    func testNativeHitRegionMatchesVisiblePillVertically() {
        let scroller = ThemedNativeScroller(frame: NSRect(x: 0, y: 0, width: 15, height: 300))
        scroller.scrollerStyle = .overlay
        scroller.isEnabled = true
        scroller.knobProportion = 0.1
        scroller.doubleValue = 0.5
        let pill = scroller.pillRect
        let hitRect = scroller.rect(for: .knob)
        XCTAssertEqual(hitRect.minY, pill.minY)
        XCTAssertEqual(hitRect.height, pill.height)
        XCTAssertGreaterThan(hitRect.width, pill.width)
        XCTAssertEqual(scroller.testPart(NSPoint(x: pill.midX, y: pill.midY)), .knob)
    }

    func testInstallerPreservesOverlayViewportAndRestoresConfiguration() throws {
        let scrollView = makeScrollView()
        scrollView.autohidesScrollers = false
        let original = try XCTUnwrap(scrollView.verticalScroller)
        let viewport = scrollView.contentView.frame
        let coordinator = NativeThemedScrollIndicator.Coordinator(style: .tinyPersistent)
        coordinator.attach(to: scrollView)
        let installed = try XCTUnwrap(scrollView.verticalScroller as? ThemedNativeScroller)
        XCTAssertEqual(scrollView.scrollerStyle, .overlay)
        XCTAssertEqual(scrollView.contentView.frame, viewport)
        XCTAssertTrue(installed.target === scrollView)
        XCTAssertNotNil(installed.action)
        coordinator.attach(to: scrollView)
        XCTAssertTrue(scrollView.verticalScroller === installed)
        var style = ScrollIndicatorStyle.tinyPersistent
        style.color = .black
        coordinator.apply(style: style)
        XCTAssertEqual(installed.indicatorStyle, style)
        coordinator.dismantle()
        XCTAssertTrue(scrollView.verticalScroller === original)
        XCTAssertFalse(scrollView.autohidesScrollers)
        XCTAssertNil(coordinator.scroller)
    }

    func testReplacementAndPreferenceChangesReinstallWithoutGutter() async throws {
        let scrollView = makeScrollView()
        let coordinator = NativeThemedScrollIndicator.Coordinator(style: .tinyPersistent)
        coordinator.attach(to: scrollView)
        let installed = try XCTUnwrap(coordinator.scroller)
        let replacement = NSScroller()
        scrollView.verticalScroller = replacement
        scrollView.scrollerStyle = .legacy
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(scrollView.verticalScroller === installed)
        XCTAssertEqual(scrollView.scrollerStyle, .overlay)
        coordinator.dismantle()
        XCTAssertTrue(scrollView.verticalScroller === replacement)
        scrollView.scrollerStyle = .legacy
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(scrollView.scrollerStyle, .legacy)
    }

    /// SwiftUI putting its scroller back every time: repairs stop at the
    /// limit and its scroller stays, instead of an endless swap.
    func testRepairsStopAtTheLimitAndSwiftUIsScrollerStays() async throws {
        let scrollView = makeScrollView()
        let coordinator = NativeThemedScrollIndicator.Coordinator(style: .tinyPersistent, now: { 0 })
        coordinator.attach(to: scrollView)
        var replacement = NSScroller()
        for _ in 0...NativeThemedScrollIndicator.Coordinator.repairLimit {
            XCTAssertFalse(coordinator.hasYieldedToSwiftUI)
            replacement = NSScroller()
            scrollView.verticalScroller = replacement
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTAssertTrue(coordinator.hasYieldedToSwiftUI)
        XCTAssertNil(coordinator.scroller)
        XCTAssertTrue(scrollView.verticalScroller === replacement, "SwiftUI's scroller stays")

        // No longer observed: another replacement is left alone.
        let later = NSScroller()
        scrollView.verticalScroller = later
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(scrollView.verticalScroller === later)
        coordinator.dismantle()
        XCTAssertTrue(scrollView.verticalScroller === later, "dismantling doesn't touch a yielded scroll view")
    }

    func testOccasionalRepairsNeverRunOut() async throws {
        let scrollView = makeScrollView()
        var time: TimeInterval = 0
        let coordinator = NativeThemedScrollIndicator.Coordinator(style: .tinyPersistent, now: { time })
        coordinator.attach(to: scrollView)
        let installed = try XCTUnwrap(coordinator.scroller)
        for _ in 0..<(NativeThemedScrollIndicator.Coordinator.repairLimit * 3) {
            time += NativeThemedScrollIndicator.Coordinator.repairWindow
            scrollView.verticalScroller = NSScroller()
            try await Task.sleep(for: .milliseconds(30))
            XCTAssertTrue(scrollView.verticalScroller === installed)
        }
        XCTAssertFalse(coordinator.hasYieldedToSwiftUI)
        coordinator.dismantle()
    }

    func testSwiftUIScrollViewGetsTheThemedScrollerWithoutGutter() async throws {
        let native = NSHostingView(rootView: scrollContent())
        native.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        let window = NSWindow(contentRect: native.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = native
        native.layoutSubtreeIfNeeded()
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(100))
        let nativeScrollView = try XCTUnwrap(findScrollView(in: native))
        XCTAssertTrue(nativeScrollView.verticalScroller is ThemedNativeScroller)
        // No gutter, whatever the system prefers ("Show scroll bars" and a
        // connected mouse can make it legacy).
        XCTAssertEqual(nativeScrollView.contentView.frame.width, native.frame.width)
        let scroller = try XCTUnwrap(nativeScrollView.verticalScroller)
        nativeScrollView.contentView.scroll(to: NSPoint(x: 0, y: 500))
        nativeScrollView.reflectScrolledClipView(nativeScrollView.contentView)
        XCTAssertGreaterThan(scroller.doubleValue, 0)
        XCTAssertLessThan(scroller.knobProportion, 1)
    }

    private func makeScrollView() -> NSScrollView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 1800))
        scrollView.tile()
        scrollView.reflectScrolledClipView(scrollView.contentView)
        return scrollView
    }

    private func scrollContent() -> some View {
        ThemedScrollView(appliesBottomEdgeEffect: true) {
            LazyVStack {
                ForEach(0..<100) { row in Text("Result \(row)").frame(height: 30) }
            }
        }
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        for child in view.subviews {
            if let scrollView = findScrollView(in: child) { return scrollView }
        }
        return nil
    }
}
