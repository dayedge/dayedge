import AppKit
import CoreImage
import QuartzCore
import SwiftUI

/// Blur and fade are direct siblings of the scroll, outside its SwiftUI content.
@MainActor
package final class ScrollEdgeDissolve {
    package enum Edge { case top, bottom }

    package struct Configuration: Equatable {
        package let fadeStrength: CGFloat
        package let opaqueHeight: CGFloat
        package let overscan: CGFloat
        package let blurRadius: CGFloat
        package let surfaceRole: SurfaceRole?

        package init(fadeStrength: CGFloat = 1, opaqueHeight: CGFloat = 0,
                     overscan: CGFloat = AppTheme.ScrollEdge.totalHeight - AppTheme.ScrollEdge.effectHeight,
                     blurRadius: CGFloat = AppTheme.ScrollEdge.blurRadius, surfaceRole: SurfaceRole? = nil) {
            self.fadeStrength = max(fadeStrength, 0.01)
            self.opaqueHeight = max(opaqueHeight, 0)
            self.overscan = max(overscan, 0)
            self.blurRadius = max(blurRadius, 0)
            self.surfaceRole = surfaceRole
        }

        var totalHeight: CGFloat { opaqueHeight + AppTheme.ScrollEdge.effectHeight + overscan }
    }

    package struct Visibility: Equatable {
        package let top: CGFloat
        package let bottom: CGFloat

        package init(metrics: ScrollMetrics, edges: VerticalEdge.Set = .all, isActive: Bool = true) {
            top = isActive && edges.contains(.top) ? ScrollEdgeDissolve.visibility(at: .top, metrics: metrics) : 0
            bottom = isActive && edges.contains(.bottom) ? ScrollEdgeDissolve.visibility(at: .bottom, metrics: metrics) : 0
        }
    }

    private let edge: Edge
    let blurView: GaussianBackdropView
    let fadeView: ContentFadeView
    private var constraints: [NSLayoutConstraint] = []
    private var heightConstraint: NSLayoutConstraint?
    private var configuration = Configuration()
    private weak var scrollView: NSScrollView?

    package init(edge: Edge) {
        self.edge = edge
        blurView = GaussianBackdropView(edge: edge)
        fadeView = ContentFadeView(edge: edge)
    }

    nonisolated package static func visibility(at edge: Edge, metrics: ScrollMetrics) -> CGFloat {
        guard metrics.maximumOffset > 0 else { return 0 }
        let distance = edge == .top ? metrics.offset : metrics.maximumOffset - metrics.offset
        return min(max(distance / AppTheme.ScrollEdge.effectHeight, 0), 1)
    }

    package func install(alongside scrollView: NSScrollView) {
        guard let container = scrollView.superview else { return }
        guard self.scrollView !== scrollView || blurView.superview !== container else { return }
        remove()
        self.scrollView = scrollView
        blurView.translatesAutoresizingMaskIntoConstraints = false
        fadeView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(blurView, positioned: .above, relativeTo: scrollView)
        container.addSubview(fadeView, positioned: .above, relativeTo: blurView)
        let height = blurView.heightAnchor.constraint(equalToConstant: configuration.totalHeight)
        heightConstraint = height
        constraints = [
            blurView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            height,
            fadeView.leadingAnchor.constraint(equalTo: blurView.leadingAnchor),
            fadeView.trailingAnchor.constraint(equalTo: blurView.trailingAnchor),
            fadeView.topAnchor.constraint(equalTo: blurView.topAnchor),
            fadeView.bottomAnchor.constraint(equalTo: blurView.bottomAnchor),
            edge == .top ? blurView.topAnchor.constraint(equalTo: scrollView.topAnchor)
                : blurView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor)
        ]
        NSLayoutConstraint.activate(constraints)
    }

    package func apply(surfaceColor: NSColor, visibility: CGFloat, blurs: Bool, configuration: Configuration = .init(),
                       material: NSVisualEffectView.Material? = nil) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if self.configuration != configuration {
            self.configuration = configuration
            heightConstraint?.constant = configuration.totalHeight
            blurView.configure(edge: edge, configuration: configuration)
            fadeView.configure(edge: edge, configuration: configuration)
        }
        let alpha = min(max(visibility, 0), 1)
        for view in [blurView, fadeView] {
            if view.alphaValue != alpha { view.alphaValue = alpha }
            if view.isHidden != (alpha == 0) { view.isHidden = alpha == 0 }
        }
        blurView.setBlurring(blurs && alpha > 0)
        fadeView.apply(surfaceColor: surfaceColor, material: material)
        CATransaction.commit()
    }

    package func remove() {
        NSLayoutConstraint.deactivate(constraints)
        constraints = []
        heightConstraint = nil
        blurView.setBlurring(false)
        blurView.removeFromSuperview()
        fadeView.removeFromSuperview()
        scrollView = nil
    }

    fileprivate static func configureGradient(_ gradient: CAGradientLayer, edge: Edge, opacities: [CGFloat],
                                              locations: [Double], configuration: Configuration) {
        let positions = locations.dropLast().map {
            Double((configuration.opaqueHeight + CGFloat($0) * AppTheme.ScrollEdge.totalHeight) / configuration.totalHeight)
        } + [1]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        gradient.colors = (edge == .bottom ? opacities : opacities.reversed()).map { NSColor.black.withAlphaComponent($0).cgColor }
        gradient.locations = (edge == .bottom ? positions : positions.reversed().map { 1 - $0 }).map { NSNumber(value: $0) }
    }
}

@MainActor
final class GaussianBackdropView: NSView {
    private let gradientMask = CAGradientLayer()
    private let blur = CIFilter(name: "CIGaussianBlur")
    private var isBlurring = false

    init(edge: ScrollEdgeDissolve.Edge) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.001).cgColor
        layer?.mask = gradientMask
        blur?.name = "scrollEdgeBlur"
        configure(edge: edge, configuration: .init())
        setAccessibilityElement(false)
    }

    func configure(edge: ScrollEdgeDissolve.Edge, configuration: ScrollEdgeDissolve.Configuration) {
        ScrollEdgeDissolve.configureGradient(gradientMask, edge: edge, opacities: [1, 1, 0.8, 0.15, 0, 0],
                                            locations: [0, 0.384, 0.496, 0.6, 0.8, 1], configuration: configuration)
        blur?.setValue(configuration.blurRadius, forKey: kCIInputRadiusKey)
        if isBlurring { backgroundFilters = blur.map { [$0] } ?? [] }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func setBlurring(_ enabled: Bool) {
        if isHidden != !enabled { isHidden = !enabled }
        guard isBlurring != enabled else { return }
        isBlurring = enabled
        backgroundFilters = enabled ? blur.map { [$0] } ?? [] : []
        layerUsesCoreImageFilters = enabled
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientMask.frame = bounds
        CATransaction.commit()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class ContentFadeView: NSView {
    private let gradient = CAGradientLayer()
    private let tintView = NSView()
    private var materialView: NSVisualEffectView?
    private var surfaceColor: NSColor?

    init(edge: ScrollEdgeDissolve.Edge) {
        super.init(frame: .zero)
        wantsLayer = true
        tintView.wantsLayer = true
        addSubview(tintView)
        configure(edge: edge, configuration: .init())
        layer?.mask = gradient
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func configure(edge: ScrollEdgeDissolve.Edge, configuration: ScrollEdgeDissolve.Configuration) {
        let profile: [CGFloat] = [1, 0.96, 0.72, 0.25, 0, 0, 0]
        let opacities = profile.map {
            1 - pow(1 - $0, configuration.fadeStrength)
        }
        ScrollEdgeDissolve.configureGradient(gradient, edge: edge, opacities: opacities,
                                            locations: [0, 0.144, 0.28, 0.448, 0.624, 0.8, 1], configuration: configuration)
    }

    func apply(surfaceColor: NSColor, material: NSVisualEffectView.Material?) {
        if materialView?.material != material {
            materialView?.removeFromSuperview()
            materialView = material.map { material in
                let view = NSVisualEffectView(frame: bounds)
                view.material = material
                view.blendingMode = .behindWindow
                view.state = .active
                view.isEmphasized = false
                addSubview(view, positioned: .below, relativeTo: tintView)
                return view
            }
        }
        guard self.surfaceColor != surfaceColor else { return }
        self.surfaceColor = surfaceColor
        tintView.layer?.backgroundColor = surfaceColor.cgColor
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        tintView.frame = bounds
        materialView?.frame = bounds
        CATransaction.commit()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
