import SwiftUI

package struct ScrollMetrics: Equatable {
    package var offset: CGFloat = 0
    package var contentHeight: CGFloat = 0
    package var viewportHeight: CGFloat = 0

    package var maximumOffset: CGFloat {
        max(contentHeight - viewportHeight, 0)
    }

    package var progress: CGFloat {
        guard maximumOffset > 0 else { return 0 }
        return min(max(offset / maximumOffset, 0), 1)
    }

    package init(offset: CGFloat = 0, contentHeight: CGFloat = 0, viewportHeight: CGFloat = 0) {
        self.offset = offset
        self.contentHeight = contentHeight
        self.viewportHeight = viewportHeight
    }
}

/// The look of the themed scroller (`NativeThemedScrollIndicator`). The
/// scroll mechanics remain AppKit's.
package struct ScrollIndicatorStyle: Equatable {
    package var width: CGFloat
    package var minimumHeight: CGFloat
    package var maximumHeight: CGFloat?
    package var color: Color
    package var opacity: Double
    package var trailingInset: CGFloat
    package var verticalInset: CGFloat
    package var shadowColor: Color
    package var shadowRadius: CGFloat

    package static let tinyPersistent = ScrollIndicatorStyle(
        width: 4,
        minimumHeight: 28,
        maximumHeight: nil,
        color: ThemePalette.opal.neutralInk,
        opacity: 0.35,
        trailingInset: 3,
        verticalInset: 3,
        shadowColor: .clear,
        shadowRadius: 0
    )
}

/// Shared native scroll surface for every calendar-facing view, with the
/// themed AppKit scroller (`NativeThemedScrollIndicator`). Scroll geometry
/// is observed only for `onMetricsChange` or the custom dissolve — a
/// per-frame observer costs on long lists. A caller only supplies a
/// position binding when it needs programmatic scrolling.
package struct ThemedScrollView<Content: View>: View {
    @Environment(\.themePalette) private var theme

    private let externalPosition: Binding<ScrollPosition>?
    private let configuredIndicatorStyle: ScrollIndicatorStyle?
    private let appliesTopEdgeEffect: Bool
    private let appliesBottomEdgeEffect: Bool
    private let edgeDissolve: VerticalEdge.Set
    private let topDissolve: ScrollEdgeDissolve.Configuration
    private let bottomDissolve: ScrollEdgeDissolve.Configuration
    private let isDissolveActive: Bool
    private let onMetricsChange: ((ScrollMetrics) -> Void)?
    private let onScrollerTracking: ((Bool) -> Void)?
    private let content: Content

    @State private var internalPosition = ScrollPosition()
    @State private var metrics = ScrollMetricsBox()
    @State private var dissolveVisibility = ScrollEdgeDissolve.Visibility(metrics: ScrollMetrics())

    /// `onScrollerTracking`: true while the scroller's knob or track is
    /// dragged — SwiftUI reports no scroll phase for that.
    package init(
        position: Binding<ScrollPosition>? = nil,
        indicatorStyle: ScrollIndicatorStyle? = nil,
        appliesTopEdgeEffect: Bool = false,
        appliesBottomEdgeEffect: Bool = false,
        edgeDissolve: VerticalEdge.Set = [],
        topDissolve: ScrollEdgeDissolve.Configuration = .init(),
        bottomDissolve: ScrollEdgeDissolve.Configuration = .init(),
        isDissolveActive: Bool = true,
        onMetricsChange: ((ScrollMetrics) -> Void)? = nil,
        onScrollerTracking: ((Bool) -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.externalPosition = position
        self.configuredIndicatorStyle = indicatorStyle
        self.appliesTopEdgeEffect = appliesTopEdgeEffect
        self.appliesBottomEdgeEffect = appliesBottomEdgeEffect
        self.edgeDissolve = edgeDissolve
        self.topDissolve = topDissolve
        self.bottomDissolve = bottomDissolve
        self.isDissolveActive = isDissolveActive
        self.onMetricsChange = onMetricsChange
        self.onScrollerTracking = onScrollerTracking
        self.content = content()
    }

    private var indicatorStyle: ScrollIndicatorStyle {
        var style = configuredIndicatorStyle ?? .tinyPersistent
        if configuredIndicatorStyle == nil { style.color = theme.neutralInk }
        return style
    }

    private var position: Binding<ScrollPosition> {
        externalPosition ?? $internalPosition
    }

    @ViewBuilder
    package var body: some View {
        let scrollView = ScrollView(.vertical) {
            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background {
                    NativeThemedScrollIndicator(style: indicatorStyle, onTracking: onScrollerTracking)
                }
                .background {
                    if !edgeDissolve.isEmpty {
                        NativeScrollEdgeDissolve(visibility: isDissolveActive ? dissolveVisibility : .init(metrics: ScrollMetrics()),
                                                topConfiguration: topDissolve, bottomConfiguration: bottomDissolve)
                    }
                }
        }
        .scrollPosition(position)

        let measuredScrollView = reportingMetrics(scrollView)
        if !edgeDissolve.isEmpty {
            measuredScrollView.hidingNativeScrollEdges()
        } else if appliesTopEdgeEffect && appliesBottomEdgeEffect {
            measuredScrollView
                .liquidGlassTopScrollEdge()
                .liquidGlassBottomScrollEdge()
        } else if appliesTopEdgeEffect {
            measuredScrollView.liquidGlassTopScrollEdge()
        } else if appliesBottomEdgeEffect {
            measuredScrollView.liquidGlassBottomScrollEdge()
        } else {
            measuredScrollView
        }
    }

    @ViewBuilder
    private func reportingMetrics<Surface: View>(_ surface: Surface) -> some View {
        if onMetricsChange != nil || !edgeDissolve.isEmpty {
            surface.onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
                let insetHeight = geometry.contentInsets.top + geometry.contentInsets.bottom
                return ScrollMetrics(
                    offset: max(0, geometry.contentOffset.y + geometry.contentInsets.top),
                    contentHeight: geometry.contentSize.height + insetHeight,
                    viewportHeight: geometry.containerSize.height
                )
            } action: { _, newMetrics in
                metrics.post(newMetrics) { value in
                    if !edgeDissolve.isEmpty {
                        let visibility = ScrollEdgeDissolve.Visibility(metrics: value, edges: edgeDissolve)
                        if visibility != dissolveVisibility { dissolveVisibility = visibility }
                    }
                    onMetricsChange?(value)
                }
            }
        } else {
            surface
        }
    }
}

/// The scroll view's latest geometry, reported to `onMetricsChange`.
@MainActor
@Observable
package final class ScrollMetricsBox {
    package private(set) var value = ScrollMetrics()
    @ObservationIgnored private var pending: ScrollMetrics?

    /// Takes new geometry from inside a layout pass and applies it on the
    /// next run-loop turn, coalesced. Writing it right away queued another
    /// update from within the one that measured it; with a lazy stack
    /// whose estimates move the content size on every pass, that never
    /// settled and the panel hung in one endless update.
    package func post(_ metrics: ScrollMetrics, then onChange: ((ScrollMetrics) -> Void)?) {
        let isScheduled = pending != nil
        pending = metrics
        guard !isScheduled else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let metrics = self.pending else { return }
            self.pending = nil
            guard metrics != self.value else { return }
            self.value = metrics
            onChange?(metrics)
        }
    }
}
