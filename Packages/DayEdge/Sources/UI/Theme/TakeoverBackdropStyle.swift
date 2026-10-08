import AppKit
import SwiftUI

/// The full description of the meeting takeover's backdrop, as data — so a
/// new look is one more static value here, not another branch in the view.
/// Layers, bottom to top: blurred desktop (material + saturation), frost
/// tint, dimming, sheen, bottom floor gradient, grain.
package struct TakeoverBackdropStyle: Equatable {
    package var material: NSVisualEffectView.Material
    package var saturation: Double
    package var frost: Color
    package var dimming: Color
    /// Diagonal specular highlight across the upper part (0 = none).
    package var sheenOpacity: Double
    /// Darkening at the very bottom, fading to clear upward (0 = none).
    package var floorOpacity: Double
    package var grainOpacity: Double

    /// Dark blur with a flat black dimming — the original takeover look.
    package static let graphite = TakeoverBackdropStyle(
        material: .fullScreenUI, saturation: 1,
        frost: .clear, dimming: ThemePalette.opal.meetingTakeover.dimming, sheenOpacity: 0,
        floorOpacity: 0, grainOpacity: 0
    )

    /// Frosted glass: a strong, light milky tint that mutes what is behind
    /// it, matte grain, and a darker floor for text contrast.
    package static let frostedGlass = TakeoverBackdropStyle(
        material: .hudWindow, saturation: 1.0,
        frost: Color.white.opacity(0.18), dimming: Color.black.opacity(0.12), sheenOpacity: 0.14,
        floorOpacity: 0.15, grainOpacity: 0.035
    )

    /// The backdrop for the stored choice. Theme follows the theme (the
    /// Graphite backdrop, dimmed and lightened as it asks); Graphite and
    /// Frosted Glass are Opal's, whatever the theme.
    package static func current(defaults: UserDefaults = .standard, theme: ThemePalette = .opal) -> TakeoverBackdropStyle {
        let choice = TakeoverBackdropChoice.stored(in: defaults)
        guard choice == .theme else { return choice.style }
        var style = TakeoverBackdropStyle.graphite
        if theme.isLight {
            style.frost = .white.opacity(0.18)
            style.floorOpacity = 0
        }
        style.dimming = theme.meetingTakeover.dimming
        return style
    }
}

/// The user-facing backdrop options for the full-screen takeover; each maps
/// to one `TakeoverBackdropStyle`.
package enum TakeoverBackdropChoice: String, CaseIterable, Identifiable {
    /// Derived from the app's theme: its colors, its appearance.
    case theme
    /// Opal's dark takeover, whatever the theme.
    case graphite
    /// Opal's frosted takeover, whatever the theme.
    case frosted

    package var id: String { rawValue }

    package var title: String {
        switch self {
        case .theme: return L10n.tr("takeoverbackdropstyle.theme", "Theme")
        case .graphite: return L10n.tr("takeoverbackdropstyle.graphite", "Graphite")
        case .frosted: return L10n.tr("takeoverbackdropstyle.frosted.glass", "Frosted Glass")
        }
    }

    package var style: TakeoverBackdropStyle {
        switch self {
        case .theme, .graphite: return .graphite
        case .frosted: return .frostedGlass
        }
    }

    package static func stored(in defaults: UserDefaults = .standard) -> TakeoverBackdropChoice {
        defaults.string(forKey: MeetingHUDSettings.takeoverBackdropKey)
            .flatMap(TakeoverBackdropChoice.init) ?? .theme
    }

    /// The takeover's whole look (controls, text, appearance) when the
    /// choice isn't the theme's: Opal's.
    package var fixedTheme: FixedTheme? {
        self == .theme ? nil : .init(palette: .opal, colorScheme: .dark)
    }
}
