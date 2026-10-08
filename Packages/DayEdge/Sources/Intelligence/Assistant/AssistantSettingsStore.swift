import Foundation
import Observation

/// Persists `AssistantSettings` — the API keys included, one per provider —
/// in its own file, `~/Library/Application Support/<app>/intelligence.json`,
/// readable by the user only (0600) and excluded from backups (Time Machine
/// and the like), so no copy of a key ends up elsewhere. Kept out of
/// `UserDefaults`, so the key isn't in the general preferences and changing
/// it doesn't trigger the app-wide defaults-change reloads. Shared by the
/// Settings window and the popover.
///
/// Not the Keychain yet: an app without an Apple team ID can't use the
/// data-protection keychain, and a login-keychain item is partitioned by the
/// exact build that saved it (`cdhash:`), so every update would ask for the
/// login password. Move the keys there once DayEdge is Developer ID signed.
@MainActor
@Observable
package final class AssistantSettingsStore {
    package private(set) var settings: AssistantSettings
    @ObservationIgnored private let fileURL: URL

    package init(fileURL: URL = AssistantSettingsStore.defaultFileURL) {
        self.fileURL = fileURL
        self.settings = Self.load(from: fileURL)
        Self.excludeFromBackup(fileURL)
    }

    /// Changes the settings and saves them.
    package func update(_ change: (inout AssistantSettings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        settings = next
        save()
    }

    package nonisolated static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("DayEdge", isDirectory: true).appendingPathComponent("intelligence.json")
    }

    /// The saved settings; local only when there's no file or it can't be read.
    package nonisolated static func load(from url: URL) -> AssistantSettings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(AssistantSettings.self, from: data) else { return .localOnly }
        return settings
    }

    /// Set after every write: an atomic save replaces the file, and the flag with it.
    package nonisolated static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    private func save() {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(settings).write(to: fileURL, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            Self.excludeFromBackup(fileURL)
        } catch {
            // Settings stay in memory for this run; nothing else depends on the file.
        }
    }
}
