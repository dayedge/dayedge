import Foundation

/// Whether the app also shows in the Dock (and the app switcher) — off by
/// default: it's a menu-bar app, and stays one either way. The Dock icon
/// shows the current month (`DockIcon`).
enum DockSettings {
    static let showsIconKey = "com.dayedge.dock.showsIcon"

    static func showsIcon(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: showsIconKey)
    }
}
