import Foundation

package enum MeetingHUDStyle: String, CaseIterable, Identifiable, Codable {
    case compact
    case fullScreen
    package var id: String { rawValue }
}

package enum MeetingHUDShowFor: String, CaseIterable, Identifiable, Codable {
    case meetingsWithLink
    case allTimedEvents
    package var id: String { rawValue }
}

package enum MeetingHUDDisplay: String, CaseIterable, Identifiable, Codable {
    case active
    case main
    case all
    package var id: String { rawValue }
}

package struct MeetingHUDConfiguration {
    package var isEnabled: Bool
    package var style: MeetingHUDStyle
    package var leadTimeMinutes: Int
    package var playsSound: Bool
    package var showFor: MeetingHUDShowFor
    package var display: MeetingHUDDisplay

    package static let `default` = MeetingHUDConfiguration(
        isEnabled: true, style: .compact, leadTimeMinutes: 5,
        playsSound: true, showFor: .meetingsWithLink, display: .active
    )
}

/// Persisted choice of `MeetingHUDConfiguration` — the one seam the
/// Settings "Meeting HUD" pane reads from and writes to; nothing else in
/// the app should read/write these keys directly.
package enum MeetingHUDSettings {
    package static let leadTimeOptions = [0, 1, 5]
    package static let enabledKey = "com.dayedge.meetingHUD.enabled"
    package static let styleKey = "com.dayedge.meetingHUD.style"
    package static let leadTimeKey = "com.dayedge.meetingHUD.leadMinutes"
    package static let playsSoundKey = "com.dayedge.meetingHUD.playsSound"
    package static let showForKey = "com.dayedge.meetingHUD.showFor"
    package static let displayKey = "com.dayedge.meetingHUD.display"
    package static let takeoverBackdropKey = "com.dayedge.meetingHUD.takeoverBackdrop"

    package static var configuration: MeetingHUDConfiguration {
        let defaults = UserDefaults.standard
        let fallback = MeetingHUDConfiguration.default
        let storedLeadTime = integer(
            forKey: leadTimeKey,
            default: fallback.leadTimeMinutes,
            defaults: defaults
        )
        return MeetingHUDConfiguration(
            isEnabled: bool(forKey: enabledKey, default: fallback.isEnabled, defaults: defaults),
            style: defaults.string(forKey: styleKey).flatMap(MeetingHUDStyle.init) ?? fallback.style,
            leadTimeMinutes: normalizedLeadTime(storedLeadTime),
            playsSound: bool(forKey: playsSoundKey, default: fallback.playsSound, defaults: defaults),
            showFor: defaults.string(forKey: showForKey).flatMap(MeetingHUDShowFor.init) ?? fallback.showFor,
            display: defaults.string(forKey: displayKey).flatMap(MeetingHUDDisplay.init) ?? fallback.display
        )
    }

    package static func normalizedLeadTime(_ value: Int) -> Int {
        leadTimeOptions.contains(value) ? value : MeetingHUDConfiguration.default.leadTimeMinutes
    }

    private static func bool(forKey key: String, default fallback: Bool, defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    private static func integer(forKey key: String, default fallback: Int, defaults: UserDefaults) -> Int {
        defaults.object(forKey: key) == nil ? fallback : defaults.integer(forKey: key)
    }
}
