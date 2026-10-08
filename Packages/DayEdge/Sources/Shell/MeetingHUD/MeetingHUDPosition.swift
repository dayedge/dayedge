import AppKit
import Foundation

/// The HUD's center, normalized to a display's own `visibleFrame` rather
/// than stored as absolute pixels — survives resolution/scaling changes,
/// Dock repositioning, and different displays having different usable
/// areas, none of which a raw point would.
struct MeetingHUDPosition: Codable, Equatable {
    /// 0...1 across `visibleFrame.width`, from `visibleFrame.minX`.
    var xNormalized: Double
    /// 0...1 across `visibleFrame.height`, from `visibleFrame.minY`.
    var yNormalized: Double
}

/// Per-display HUD position memory — keyed by `CGDirectDisplayID`, not
/// `NSScreen` array index (which can reorder when displays are
/// connected/disconnected) and not a single global position (a MacBook's
/// built-in display and a 32" external monitor want very different
/// defaults).
enum MeetingHUDPositionStore {
    private static func key(for displayID: CGDirectDisplayID) -> String {
        "com.dayedge.meetingHUD.position.\(displayID)"
    }

    static func position(for displayID: CGDirectDisplayID) -> MeetingHUDPosition? {
        guard let data = UserDefaults.standard.data(forKey: key(for: displayID)) else { return nil }
        return try? JSONDecoder().decode(MeetingHUDPosition.self, from: data)
    }

    static func setPosition(_ position: MeetingHUDPosition, for displayID: CGDirectDisplayID) {
        guard let data = try? JSONEncoder().encode(position) else { return }
        UserDefaults.standard.set(data, forKey: key(for: displayID))
    }

    static func resetPosition(for displayID: CGDirectDisplayID) {
        UserDefaults.standard.removeObject(forKey: key(for: displayID))
    }
}

extension NSScreen {
    /// The stable per-monitor identity `MeetingHUDPositionStore` keys
    /// positions against — not derived from `NSScreen.screens`' array
    /// index, which can change when a display is connected/disconnected.
    var stableDisplayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
