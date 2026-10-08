import AppKit
import Observation
import SwiftUI

/// A catalog entry owns all theme-specific decisions; views only consume its palette.
package struct ThemeDefinition: Identifiable {
    package enum AppearancePolicy {
        case light, dark, system

        package func resolvedScheme(system: ColorScheme) -> ColorScheme {
            switch self {
            case .light: return .light
            case .dark: return .dark
            case .system: return system
            }
        }
    }

    package let id: String
    package let title: String
    package let appearance: AppearancePolicy
    package let palette: (ColorScheme) -> ThemePalette
}

package enum ThemeCatalog {
    package static let themes: [ThemeDefinition] = [
        .init(id: "opal", title: L10n.tr("appearancestore.opal", "Opal"), appearance: .dark, palette: { _ in .opal }),
        .init(id: "apple-light", title: L10n.tr("appearancestore.light", "Light"), appearance: .light, palette: { _ in .appleLight }),
        .init(id: "apple-dark", title: L10n.tr("appearancestore.dark", "Dark"), appearance: .dark, palette: { _ in .appleDark }),
        .init(
            id: "apple-system", title: L10n.tr("appearancestore.system", "System"), appearance: .system,
            palette: { $0 == .light ? .appleSystemLight : .appleSystemDark }),
        .init(id: "one-dark-pro", title: L10n.tr("appearancestore.one.dark.pro", "One Dark Pro"), appearance: .dark, palette: { _ in .oneDarkPro }),
        .init(id: "graphite-pro", title: L10n.tr("appearancestore.graphite.pro", "Graphite Pro"), appearance: .dark, palette: { _ in .graphitePro }),
        .init(id: "quartz-pro", title: L10n.tr("appearancestore.quartz.pro", "Quartz Pro"), appearance: .light, palette: { _ in .quartzPro }),
        .init(id: "frost", title: L10n.tr("appearancestore.frost", "Frost"), appearance: .system, palette: { $0 == .light ? .frostLight : .frostDark })
    ]

    /// The theme on first launch, and for a saved id that no longer exists.
    package static let defaultID = "graphite-pro"

    package static func theme(id: String?) -> ThemeDefinition {
        themes.first { $0.id == id } ?? themes.first { $0.id == defaultID } ?? themes[0]
    }
}

@MainActor
@Observable
package final class AppearanceStore {
    package static let themeKey = "appearance.theme"
    package static let shared = AppearanceStore()

    package private(set) var themeID: String
    package private(set) var systemScheme: ColorScheme
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?
    @ObservationIgnored private var defaultsObservation: NSObjectProtocol?

    package init(defaults: UserDefaults = .standard, observesSystem: Bool = true, systemScheme: ColorScheme = .light) {
        self.defaults = defaults
        themeID = ThemeCatalog.theme(id: defaults.string(forKey: Self.themeKey)).id
        self.systemScheme = systemScheme
        if observesSystem {
            updateSystemAppearance(NSApplication.shared.effectiveAppearance)
            appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance, options: [.new]) { [weak self] app, _ in
                Task { @MainActor in self?.updateSystemAppearance(app.effectiveAppearance) }
            }
            defaultsObservation = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification, object: defaults, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.reloadSelection() }
            }
        }
    }

    package var definition: ThemeDefinition { ThemeCatalog.theme(id: themeID) }
    package var colorScheme: ColorScheme { definition.appearance.resolvedScheme(system: systemScheme) }
    package var palette: ThemePalette { definition.palette(colorScheme) }
    package var preferredColorScheme: ColorScheme? {
        switch definition.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    package func selectTheme(_ id: String) {
        themeID = ThemeCatalog.theme(id: id).id
        defaults.set(themeID, forKey: Self.themeKey)
    }

    package func updateSystemAppearance(_ appearance: NSAppearance) {
        systemScheme = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }

    private func reloadSelection() {
        themeID = ThemeCatalog.theme(id: defaults.string(forKey: Self.themeKey)).id
    }

    deinit {
        if let defaultsObservation { NotificationCenter.default.removeObserver(defaultsObservation) }
    }
}

/// Each separately hosted SwiftUI tree gets the same store, without replacing view identity.
/// A palette and appearance used in place of the chosen theme's.
package struct FixedTheme {
    package var palette: ThemePalette
    package var colorScheme: ColorScheme
}

package struct ThemedRoot<Content: View>: View {
    package let content: Content
    package var usesWindowBackground = false
    package var appearance: AppearanceStore = .shared
    /// A look that ignores the chosen theme (the takeover's Graphite and
    /// Frosted Glass backgrounds).
    package var fixedTheme: FixedTheme?

    /// `appearance` nil: the app's shared store.
    @MainActor
    package init(content: Content, usesWindowBackground: Bool = false, appearance: AppearanceStore? = nil,
                 fixedTheme: FixedTheme? = nil) {
        self.content = content
        self.usesWindowBackground = usesWindowBackground
        self.appearance = appearance ?? .shared
        self.fixedTheme = fixedTheme
    }

    private var palette: ThemePalette { fixedTheme?.palette ?? appearance.palette }
    private var colorScheme: ColorScheme { fixedTheme?.colorScheme ?? appearance.colorScheme }

    package var body: some View {
        content
            .environment(\.themePalette, palette)
            .environment(appearance)
            .modifier(FormatProvider())
            .tint(palette.nativeControlAccent)
            // Always the resolved scheme, never nil: "System" resolves to
            // the Mac's (observed), so switching between explicit and
            // system themes never relies on nil restoring what an explicit
            // scheme set — it didn't always, leaving AppKit controls in the
            // old appearance (white text on a white field, missing title
            // bar buttons).
            .preferredColorScheme(colorScheme)
            .background(
                ThemeWindowAppearance(
                    scheme: colorScheme,
                    background: usesWindowBackground ? palette.settings.background : nil,
                    materialWindow: usesWindowBackground && palette.surfaces != nil
                ))
    }
}

/// SwiftUI color scheme alone doesn't update AppKit title bars, menus and materials.
private struct ThemeWindowAppearance: NSViewRepresentable {
    let scheme: ColorScheme
    let background: Color?
    let materialWindow: Bool

    /// Applies only what changed: re-setting the window's appearance,
    /// opacity and background on every SwiftUI update made AppKit redo the
    /// whole window each time, and it sometimes ended half-updated.
    final class Anchor: NSView {
        var scheme: ColorScheme = .light
        var fill: Color?
        var materialWindow = false
        var previousOpaque: Bool?
        private var applied: WindowLook?
        private weak var appliedWindow: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        func apply() {
            guard let window else { return }
            let look = WindowLook(scheme: scheme, fill: fill, materialWindow: materialWindow)
            if appliedWindow === window, applied == look { return }
            let name: NSAppearance.Name = scheme == .dark ? .darkAqua : .aqua
            if window.appearance?.name != name { window.appearance = NSAppearance(named: name) }
            applyBackground(to: window)
            // The frame (title bar buttons included) and shadow redrawn
            // in the new appearance, not left from the old one.
            window.invalidateShadow()
            window.contentView?.superview?.needsDisplay = true
            applied = look
            appliedWindow = window
            // AppKit sometimes drops the traffic lights while it redoes the
            // frame (and SwiftUI rebuilds the content) for the new
            // appearance: checked once that settles, and brought back.
            for delay in [0.0, 0.3] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak window] in
                    guard let window else { return }
                    Self.restoreWindowButtons(in: window)
                }
            }
        }

        /// A material window is see-through (its opacity restored after);
        /// otherwise the theme's fill.
        private func applyBackground(to window: NSWindow) {
            if materialWindow {
                if previousOpaque == nil { previousOpaque = window.isOpaque }
                if window.isOpaque { window.isOpaque = false }
                if window.backgroundColor != .clear { window.backgroundColor = .clear }
            } else {
                if let previousOpaque { window.isOpaque = previousOpaque; self.previousOpaque = nil }
                if let fill { window.backgroundColor = NSColor(fill) }
            }
        }

        private static func restoreWindowButtons(in window: NSWindow) {
            guard window.styleMask.contains(.titled) else { return }
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                guard let button = window.standardWindowButton(kind) else { continue }
                var views: [NSView] = [button]
                if let container = button.superview { views.append(container) }
                if let titlebar = button.superview?.superview { views.append(titlebar) }
                for view in views where view.isHidden || view.alphaValue < 1 {
                    view.isHidden = false
                    view.alphaValue = 1
                }
                button.needsDisplay = true
            }
        }
    }

    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) {
        view.scheme = scheme
        view.fill = background
        view.materialWindow = materialWindow
        view.apply()
    }
}

/// What a window was last given, so an unchanged look isn't reapplied.
private struct WindowLook: Equatable {
    var scheme: ColorScheme
    var fill: Color?
    var materialWindow: Bool
}
