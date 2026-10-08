import AppKit
import UI

/// Display policy shared by the compact and full-screen presenters. IDs, rather
/// than `NSScreen` positions, survive a reordering of `NSScreen.screens`.
enum MeetingHUDDisplaySelection {
    static func selectedIDs(
        for choice: MeetingHUDDisplay,
        availableIDs: [CGDirectDisplayID],
        pointerID: CGDirectDisplayID?,
        keyWindowID: CGDirectDisplayID?
    ) -> [CGDirectDisplayID] {
        guard let mainID = availableIDs.first else { return [] }
        switch choice {
        case .active:
            return [pointerID, keyWindowID, mainID].compactMap { $0 }
                .first(where: availableIDs.contains).map { [$0] } ?? [mainID]
        case .main:
            return [mainID]
        case .all:
            return availableIDs
        }
    }

    static func screens(for choice: MeetingHUDDisplay) -> [NSScreen] {
        let screens = NSScreen.screens
        let ids = selectedIDs(
            for: choice,
            availableIDs: screens.compactMap(\.stableDisplayID),
            pointerID: screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })?.stableDisplayID,
            keyWindowID: NSApp.keyWindow?.screen?.stableDisplayID
        )
        return ids.compactMap { id in screens.first { $0.stableDisplayID == id } }
    }
}
