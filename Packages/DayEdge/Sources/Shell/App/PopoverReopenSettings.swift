import Foundation
import Agenda

/// How long after hiding the popover a reopen still counts as "the same
/// session" — `PopoverPresentationCoordinator.willOpen` reads this to
/// decide `.preserve` (restore the previous selected date, active view,
/// and scroll position — nothing to do, since the window's content never
/// actually gets torn down) vs `.todayNow` (treat it as a fresh open:
/// select today and resolve a fresh `AgendaNowTarget` via the existing
/// `preferredNowTarget(on:events:now:)`, the same logic used everywhere
/// else "jump to today" happens).
///
/// `0` means never restore — every open is treated as fresh regardless of
/// how quickly it follows the last close.
enum PopoverReopenSettings {
    static let timeoutMinutesKey = "com.dayedge.popover.reopenTimeoutMinutes"

    /// Presets surfaced in Settings — 0 ("Off") through 30 minutes.
    static let presetMinutes = [0, 1, 5, 10, 30]

    static let defaultMinutes = 10

    static var timeoutMinutes: Int {
        UserDefaults.standard.object(forKey: timeoutMinutesKey) == nil
            ? defaultMinutes
            : UserDefaults.standard.integer(forKey: timeoutMinutesKey)
    }

    static var timeoutInterval: TimeInterval {
        TimeInterval(timeoutMinutes * 60)
    }
}
