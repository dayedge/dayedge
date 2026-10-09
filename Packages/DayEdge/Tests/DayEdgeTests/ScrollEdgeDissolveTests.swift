import AppKit
import SwiftUI
import XCTest
@testable import UI

@MainActor
final class ScrollEdgeDissolveTests: XCTestCase {
    func testTopEdgeIsHiddenAtStart() {
        XCTAssertEqual(ScrollEdgeDissolve.visibility(at: .top, metrics: metrics(offset: 0)), 0)
    }

    func testBottomEdgeIsHiddenAtEnd() {
        XCTAssertEqual(ScrollEdgeDissolve.visibility(at: .bottom, metrics: metrics(offset: 600)), 0)
    }

    func testTopEdgeGraduallyAppears() {
        XCTAssertEqual(ScrollEdgeDissolve.visibility(at: .top, metrics: metrics(offset: 32)), 0.5)
    }

    func testBottomEdgeGraduallyDisappears() {
        XCTAssertEqual(ScrollEdgeDissolve.visibility(at: .bottom, metrics: metrics(offset: 568)), 0.5)
    }

    func testVisibilityDoesNotExceedOne() {
        XCTAssertEqual(ScrollEdgeDissolve.visibility(at: .top, metrics: metrics(offset: 300)), 1)
    }

    func testOverscrollingDoesNotMakeVisibilityNegative() {
        XCTAssertEqual(ScrollEdgeDissolve.visibility(at: .bottom, metrics: metrics(offset: 700)), 0)
    }

    func testContentThatFitsDoesNotDissolve() {
        let metrics = ScrollMetrics(offset: 10, contentHeight: 200, viewportHeight: 400)
        XCTAssertEqual(ScrollEdgeDissolve.visibility(at: .top, metrics: metrics), 0)
        XCTAssertEqual(ScrollEdgeDissolve.visibility(at: .bottom, metrics: metrics), 0)
    }

    func testBottomOnlyDissolveKeepsTopEdgeClear() {
        let visibility = ScrollEdgeDissolve.Visibility(metrics: metrics(offset: 300), edges: .bottom)
        XCTAssertEqual(visibility.top, 0)
        XCTAssertEqual(visibility.bottom, 1)
    }

    func testInactiveScrollHidesBothEdges() {
        let visibility = ScrollEdgeDissolve.Visibility(metrics: metrics(offset: 300), isActive: false)
        XCTAssertEqual(visibility.top, 0)
        XCTAssertEqual(visibility.bottom, 0)
    }

    func testOverlayDoesNotInterceptInput() {
        let effect = ScrollEdgeDissolve(edge: .top)
        effect.apply(surfaceColor: .white, visibility: 1, blurs: true)
        XCTAssertNil(effect.blurView.hitTest(NSPoint(x: 20, y: 40)))
        XCTAssertNil(effect.fadeView.hitTest(NSPoint(x: 20, y: 40)))
    }

    func testHiddenEdgeReleasesBackdropFilters() {
        let effect = ScrollEdgeDissolve(edge: .bottom)
        effect.apply(surfaceColor: .white, visibility: 1, blurs: true)
        XCTAssertFalse(effect.blurView.backgroundFilters.isEmpty)
        effect.apply(surfaceColor: .white, visibility: 0, blurs: true)
        XCTAssertTrue(effect.fadeView.isHidden)
        XCTAssertTrue(effect.blurView.backgroundFilters.isEmpty)
        XCTAssertFalse(effect.blurView.layerUsesCoreImageFilters)
    }

    func testAccessibilityDisablesBackdropWithoutHidingFade() {
        let effect = ScrollEdgeDissolve(edge: .bottom)
        effect.apply(surfaceColor: .white, visibility: 1, blurs: true)
        effect.apply(surfaceColor: .white, visibility: 1, blurs: false)
        XCTAssertTrue(effect.blurView.backgroundFilters.isEmpty)
        XCTAssertFalse(effect.blurView.layerUsesCoreImageFilters)
        XCTAssertFalse(effect.fadeView.isHidden)
    }

    func testEffectsAreDirectSiblingsBetweenScrollAndControls() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        let scrollView = NSScrollView(frame: container.bounds)
        let controls = NSView()
        container.addSubview(scrollView)
        container.addSubview(controls)
        let effect = ScrollEdgeDissolve(edge: .bottom)
        effect.install(alongside: scrollView)
        XCTAssertTrue(container.subviews.elementsEqual([scrollView, effect.blurView, effect.fadeView, controls], by: { $0 === $1 }))
    }

    func testRepeatedInstallDoesNotDuplicateEffects() {
        let container = NSView()
        let scrollView = NSScrollView()
        container.addSubview(scrollView)
        let effect = ScrollEdgeDissolve(edge: .top)
        effect.install(alongside: scrollView)
        effect.install(alongside: scrollView)
        XCTAssertEqual(container.subviews.count, 3)
    }

    func testDismantleRemovesEffectsAndKeepsScrollAndControls() {
        let container = NSView()
        let scrollView = NSScrollView()
        let controls = NSView()
        container.addSubview(scrollView)
        container.addSubview(controls)
        let coordinator = NativeScrollEdgeDissolve.Coordinator()
        coordinator.attach(to: scrollView)
        coordinator.dismantle()
        XCTAssertTrue(container.subviews.elementsEqual([scrollView, controls], by: { $0 === $1 }))
        XCTAssertTrue(coordinator.top.blurView.backgroundFilters.isEmpty)
        coordinator.attach(to: scrollView)
        XCTAssertEqual(container.subviews.count, 2)
    }

    func testDissolveCoversTheAreaUnderFixedBars() async throws {
        let content = ThemedScrollView(edgeDissolve: .all) {
            Color.clear.frame(height: 1000)
        }
        .floatingTopBar(usesNativeEffect: false) { Color.clear.frame(height: 20) }
        .floatingFooterBar(usesNativeEffect: false) { Color.clear.frame(height: 40) }
        let hosting = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        defer { window.contentView = nil }
        hosting.layoutSubtreeIfNeeded()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        hosting.layoutSubtreeIfNeeded()
        let backdrops = backdropViews(in: hosting)
        let frames = backdrops.map { $0.convert($0.bounds, to: hosting) }
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(try XCTUnwrap(frames.map(\.minY).min()), hosting.bounds.minY, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(frames.map(\.maxY).max()), hosting.bounds.maxY, accuracy: 0.5)
        let scrollView = try XCTUnwrap(backdrops.first?.superview?.subviews.compactMap { $0 as? NSScrollView }.first)
        XCTAssertTrue(backdrops.allSatisfy { $0.superview === scrollView.superview })
    }

    private func backdropViews(in view: NSView) -> [GaussianBackdropView] {
        if let backdrop = view as? GaussianBackdropView { return [backdrop] }
        return view.subviews.flatMap { backdropViews(in: $0) }
    }

    private func metrics(offset: CGFloat) -> ScrollMetrics {
        ScrollMetrics(offset: offset, contentHeight: 1000, viewportHeight: 400)
    }
}
