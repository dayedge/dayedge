import AppKit

/// Opens the Reminders app. Deep-linking to one reminder isn't reliable, so
/// this just brings the app forward.
package enum RemindersBridge {
    package static let bundleID = "com.apple.reminders"

    package static func open() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
