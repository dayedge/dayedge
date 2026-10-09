import AppKit
import SwiftUI

/// Only the probe lives in SwiftUI; the effects are installed beside its native scroll view.
package struct NativeScrollEdgeDissolve: NSViewRepresentable {
    @Environment(\.themePalette) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    package let visibility: ScrollEdgeDissolve.Visibility
    package var topConfiguration = ScrollEdgeDissolve.Configuration()
    package var bottomConfiguration = ScrollEdgeDissolve.Configuration()

    package func makeCoordinator() -> Coordinator { Coordinator() }

    package func makeNSView(context: Context) -> NativeThemedScrollIndicator.ProbeView {
        let probe = NativeThemedScrollIndicator.ProbeView()
        probe.onHierarchyChange = { [weak coordinator = context.coordinator, weak probe] in
            coordinator?.scheduleAttachment(of: probe)
        }
        context.coordinator.scheduleAttachment(of: probe)
        return probe
    }

    package func updateNSView(_ probe: NativeThemedScrollIndicator.ProbeView, context: Context) {
        context.coordinator.apply(topSurface: surface(for: topConfiguration), bottomSurface: surface(for: bottomConfiguration), visibility: visibility,
                                  blurs: !reduceTransparency && contrast != .increased,
                                  topConfiguration: topConfiguration, bottomConfiguration: bottomConfiguration)
    }

    private func surface(for configuration: ScrollEdgeDissolve.Configuration) -> (color: NSColor, material: NSVisualEffectView.Material?) {
        let treatment = configuration.surfaceRole.flatMap { theme.surfaces?[$0] }
        let color = NSColor(treatment?.tint ?? theme.background)
        if let treatment, !reduceTransparency, case .desktop(let material) = treatment.backing {
            let opacity = treatment.effectiveOpacity(reduceTransparency: false, increaseContrast: contrast == .increased)
            return (color.withAlphaComponent(color.alphaComponent * opacity), material)
        }
        return (color, nil)
    }

    package static func dismantleNSView(_ probe: NativeThemedScrollIndicator.ProbeView, coordinator: Coordinator) {
        probe.onHierarchyChange = nil
        coordinator.dismantle()
    }

    @MainActor
    package final class Coordinator {
        let top = ScrollEdgeDissolve(edge: .top)
        let bottom = ScrollEdgeDissolve(edge: .bottom)
        private weak var probe: NSView?
        private var attachmentScheduled = false
        private var isDismantled = false
        private var topSurface: (color: NSColor, material: NSVisualEffectView.Material?) = (.clear, nil)
        private var bottomSurface: (color: NSColor, material: NSVisualEffectView.Material?) = (.clear, nil)
        private var visibility = ScrollEdgeDissolve.Visibility(metrics: ScrollMetrics())
        private var blurs = false
        private var topConfiguration = ScrollEdgeDissolve.Configuration()
        private var bottomConfiguration = ScrollEdgeDissolve.Configuration()

        package func scheduleAttachment(of probe: NSView?) {
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
            guard !isDismantled else { return }
            if let scrollView {
                top.install(alongside: scrollView)
                bottom.install(alongside: scrollView)
                applyEffects()
            } else {
                top.remove()
                bottom.remove()
            }
        }

        package func apply(topSurface: (color: NSColor, material: NSVisualEffectView.Material?),
                           bottomSurface: (color: NSColor, material: NSVisualEffectView.Material?),
                           visibility: ScrollEdgeDissolve.Visibility, blurs: Bool,
                           topConfiguration: ScrollEdgeDissolve.Configuration, bottomConfiguration: ScrollEdgeDissolve.Configuration) {
            self.topSurface = topSurface
            self.bottomSurface = bottomSurface
            self.visibility = visibility
            self.blurs = blurs
            self.topConfiguration = topConfiguration
            self.bottomConfiguration = bottomConfiguration
            applyEffects()
        }

        private func applyEffects() {
            top.apply(surfaceColor: topSurface.color, visibility: visibility.top, blurs: blurs,
                      configuration: topConfiguration, material: topSurface.material)
            bottom.apply(surfaceColor: bottomSurface.color, visibility: visibility.bottom, blurs: blurs,
                         configuration: bottomConfiguration, material: bottomSurface.material)
        }

        package func dismantle() {
            isDismantled = true
            probe = nil
            top.remove()
            bottom.remove()
        }
    }
}

extension View {
    @ViewBuilder
    package func hidingNativeScrollEdges() -> some View {
        #if HAS_MACOS26_SDK
        if #available(macOS 26.0, *) {
            scrollEdgeEffectHidden(true, for: .vertical)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
