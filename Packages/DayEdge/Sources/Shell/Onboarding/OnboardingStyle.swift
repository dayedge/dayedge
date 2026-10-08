import AppKit
import SwiftUI

/// The landing page's look, in native terms: its colour tokens (light and
/// dark) and type scale. Onboarding draws only with these.
enum OnboardingStyle {
    static let background = color(light: 0xfafaf8, dark: 0x121315)
    static let text = color(light: 0x202125, dark: 0xededef)
    static let muted = color(light: 0x595c63, dark: 0xa3a6ad)
    static let quiet = color(light: 0x666970, dark: 0x91949c)
    static let line = color(light: 0xdeded9, dark: 0x2c2d32)
    static let accent = color(light: 0xb44a40, dark: 0xe88b83)
    /// The primary button: the text colour, labelled in the background's.
    static let button = text
    static let buttonLabel = background
    static let screenshotOutline = Color(nsColor: NSColor(name: nil) { appearance in
        isDark(appearance) ? .white.withAlphaComponent(0.25) : .black.withAlphaComponent(0.17)
    })
    static let screenshotShadow = Color(nsColor: NSColor(name: nil) { appearance in
        isDark(appearance) ? .black.withAlphaComponent(0.42) : NSColor(white: 0.1, alpha: 0.15)
    })

    // MARK: Type

    /// "Your day, / closer." — tight, editorial.
    static let hero = Font.system(size: 44, weight: .semibold)
    static let heroTracking: CGFloat = -2.6
    /// A step's title.
    static let title = Font.system(size: 22, weight: .semibold)
    static let titleTracking: CGFloat = -0.6
    static let lede = Font.system(size: 13.5)
    static let eyebrow = Font.system(size: 10, weight: .medium)
    static let eyebrowTracking: CGFloat = 1.1
    static let small = Font.system(size: 11)

    private static func color(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in rgb(isDark(appearance) ? dark : light) })
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private static func rgb(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}

/// The site's primary button: filled with the text colour, 6 pt corners.
struct OnboardingPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(OnboardingStyle.buttonLabel)
            .padding(.horizontal, 16)
            .frame(minHeight: 30)
            .background(OnboardingStyle.button.opacity(configuration.isPressed ? 0.8 : 1),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .opacity(isEnabled ? 1 : 0.5)
    }
}

/// Quiet text buttons (Back, Not now, Choose City).
struct OnboardingQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(configuration.isPressed ? OnboardingStyle.text : OnboardingStyle.muted)
            .padding(.horizontal, 8)
            .frame(minHeight: 30)
            .contentShape(Rectangle())
    }
}

/// The onboarding images (`Resources/Onboarding`, from the landing page).
enum OnboardingImage {
    static func named(_ name: String, _ ext: String = "webp") -> NSImage? {
        let url = Bundle.module.url(forResource: name, withExtension: ext)
            ?? Bundle.module.url(forResource: name, withExtension: ext, subdirectory: L10n.tr("onboardingstyle.onboarding", "Onboarding"))
        return url.flatMap(NSImage.init(contentsOf:))
    }
}
