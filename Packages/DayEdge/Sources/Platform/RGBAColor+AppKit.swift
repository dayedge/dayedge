import AppKit
import Domain

extension RGBAColor {
    /// An AppKit color (EventKit's calendar colors) in sRGB.
    package init(_ color: NSColor) {
        let srgb = color.usingColorSpace(.sRGB) ?? .gray
        self.init(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent, alpha: srgb.alphaComponent)
    }
}
