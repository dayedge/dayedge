import SwiftUI
import AppKit

/// Renders a bundled single-color SVG (from `Resources/`) as a tintable
/// icon — loaded as an `NSImage` template so SwiftUI's `.foregroundStyle`
/// recolors it the same way it would an SF Symbol, rather than showing the
/// SVG's own baked-in black.
package struct BrandIcon: View {
    package let resourceName: String

    /// Decoded once per distinct resource and reused — without this,
    /// every `body` evaluation (any parent re-render) re-reads the SVG
    /// off disk and re-decodes it.
    private static var cache: [String: NSImage] = [:]

    private var templateImage: NSImage? {
        if let cached = Self.cache[resourceName] { return cached }
        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        Self.cache[resourceName] = image
        return image
    }

    package var body: some View {
        if let templateImage {
            Image(nsImage: templateImage)
                .resizable()
                .scaledToFit()
        } else {
            // Missing resource shouldn't be possible in a shipped build,
            // but fail visibly rather than silently rendering nothing.
            Image(systemName: "video.fill")
        }
    }

    package init(resourceName: String) {
        self.resourceName = resourceName
    }
}
