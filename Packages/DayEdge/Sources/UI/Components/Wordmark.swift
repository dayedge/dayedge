import CoreText
import SwiftUI

/// The product wordmark — "Day/Edge" in Bricolage Grotesque (bundled,
/// SIL Open Font License: `Resources/BricolageGrotesque-OFL.txt`), as on
/// the website: **Day** semibold in the primary tone, a light, muted,
/// slightly raised slash, **Edge** medium and a little softer than Day.
/// Tracking −0.045 em; 0.4 pt before the slash, 0.18 pt after it.
///
/// Only where the brand is presented (About); elsewhere the name is plain
/// text.
package struct Wordmark: View {
    @Environment(\.themePalette) private var theme

    /// 22 pt; 18 pt for smaller placements.
    package var size: CGFloat = 22

    package var body: some View {
        wordmark
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("DayEdge")
    }

    /// Kerning applies after a run's last letter too, so each run's own
    /// kerning sets the gap that follows it.
    private var wordmark: Text {
        let tracking: CGFloat = -0.045 * size
        let day: Font = Self.font(weight: 600, size: size)
        let da: Text = Text("Da").font(day).kerning(tracking).foregroundColor(theme.wordmarkDay)
        let y: Text = Text("y").font(day).kerning(tracking + 0.4).foregroundColor(theme.wordmarkDay)
        let slash: Text = Text("/").font(Self.font(weight: 350, size: size)).kerning(tracking + 0.18)
            .baselineOffset(0.33).foregroundColor(theme.wordmarkSlash)
        let edge: Text = Text("Edge").font(Self.font(weight: 500, size: size)).kerning(tracking)
            .foregroundColor(theme.wordmarkEdge)
        return da + y + slash + edge
    }

    /// The bundled variable font at `weight`, its optical size following
    /// the point size (as a browser's `font-optical-sizing: auto` does),
    /// normal width. Falls back to the system font if the file is missing.
    package static func font(weight: CGFloat, size: CGFloat) -> Font {
        guard let base = baseDescriptor else {
            return .system(size: size, weight: weight >= 550 ? .semibold : weight >= 450 ? .medium : .light)
        }
        let variation: [NSNumber: NSNumber] = [
            NSNumber(value: axis("wght")): NSNumber(value: Double(weight)),
            NSNumber(value: axis("opsz")): NSNumber(value: Double(min(max(size, 12), 96))),
            NSNumber(value: axis("wdth")): 100
        ]
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(
            base, [kCTFontVariationAttribute: variation] as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
    }

    package static let baseDescriptor: CTFontDescriptor? = {
        guard let url = Bundle.module.url(forResource: "BricolageGrotesque", withExtension: "ttf"),
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]
        else { return nil }
        return descriptors.first
    }()

    /// A variation axis's four-character tag as its number.
    private static func axis(_ tag: String) -> UInt32 {
        tag.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }

    package init(size: CGFloat = 22) {
        self.size = size
    }
}
