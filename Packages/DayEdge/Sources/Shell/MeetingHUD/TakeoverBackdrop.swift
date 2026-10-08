import AppKit
import CoreImage
import SwiftUI
import UI

/// Renders a `TakeoverBackdropStyle` behind the takeover content. Increased
/// contrast swaps the tint/dimming for the stronger high-contrast dimming;
/// Reduce Transparency replaces everything with a solid color.
struct TakeoverBackdrop: View {
    @Environment(\.themePalette) private var theme

    let style: TakeoverBackdropStyle
    let reduceTransparency: Bool
    let increasedContrast: Bool

    var body: some View {
        ZStack {
            if reduceTransparency {
                theme.meetingTakeover.opaqueFallback
            } else {
                TakeoverBlur(material: style.material)
                    .saturation(style.saturation)
                if !increasedContrast { style.frost }
                increasedContrast ? theme.meetingTakeover.highContrastDimming : style.dimming
                if style.sheenOpacity > 0 && !increasedContrast {
                    // A soft glossy streak: bright at the top-left corner,
                    // easing off, with a faint second band lower right.
                    LinearGradient(
                        stops: [
                            .init(color: theme.meetingTakeover.sheen.opacity(style.sheenOpacity), location: 0),
                            .init(color: .clear, location: 0.42),
                            .init(color: theme.meetingTakeover.sheen.opacity(style.sheenOpacity * 0.35), location: 0.72),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .allowsHitTesting(false)
                }
                if style.floorOpacity > 0 {
                    LinearGradient(
                        colors: [.clear, theme.meetingTakeover.floor.opacity(style.floorOpacity)],
                        startPoint: .center, endPoint: .bottom
                    )
                }
                if style.grainOpacity > 0 {
                    Image(nsImage: TakeoverGrain.tile)
                        .resizable(resizingMode: .tile)
                        .opacity(style.grainOpacity)
                        .allowsHitTesting(false)
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Inherits the themed window appearance so native blur follows the palette.
private struct TakeoverBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = material
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// A small monochrome noise tile, generated once and repeated.
private enum TakeoverGrain {
    static let tile: NSImage = {
        let size = 128
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        guard let noise = CIFilter(name: "CIRandomGenerator")?.outputImage?.cropped(to: rect),
              let mono = CIFilter(name: "CIColorControls", parameters: [
                  kCIInputImageKey: noise, kCIInputSaturationKey: 0
              ])?.outputImage,
              let cg = CIContext().createCGImage(mono, from: rect) else { return NSImage() }
        return NSImage(cgImage: cg, size: NSSize(width: size, height: size))
    }()
}
