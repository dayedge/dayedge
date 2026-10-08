import AppKit
import EventKit
import Foundation
import Domain
import UI

extension MeetingHUDController {
    /// Join is a permanent dismissal, not a snooze — the occurrence must
    /// never resurface again after the user has actually joined it, even
    /// though the meeting itself is still ongoing.
    func join(_ occurrence: MeetingHUDOccurrence) {
        dismissedOccurrenceIDs.insert(occurrence.id)
        currentlyShown = nil
        hidePresented(restoreFocus: false)
        if let url = occurrence.meetingURL { openURL(url) }
    }

    /// The one-click primary Snooze action — "come back exactly when I
    /// need to join." Before the meeting starts that means the exact
    /// start time; once it's started, "exact start" is no longer a
    /// meaningful target, so it falls back to a one-minute reminder.
    /// `now() < occurrence.start`
    /// being false at *exact* equality is deliberate — an event that has
    /// just started is "started," not "about to start."
    func snoozeSmart(_ occurrence: MeetingHUDOccurrence) {
        if now() < occurrence.start {
            applySnooze(occurrence, mode: .untilMeetingStart, wakeAt: occurrence.start)
        } else {
            applySnooze(occurrence, mode: .duration(60), wakeAt: now().addingTimeInterval(60))
        }
    }

    /// The overflow menu's 5/10-minute options — always relative to now,
    /// never to the meeting's start, regardless of whether it has
    /// started yet ("leave me alone for another N minutes").
    func snoozeForDuration(_ occurrence: MeetingHUDOccurrence, duration: TimeInterval) {
        applySnooze(occurrence, mode: .duration(duration), wakeAt: now().addingTimeInterval(duration))
    }

    private func applySnooze(_ occurrence: MeetingHUDOccurrence, mode: MeetingHUDSnoozeMode, wakeAt: Date) {
        snoozeStateByOccurrenceID[occurrence.id] = MeetingHUDSnoozeState(
            occurrenceID: occurrence.id, reminderOccurrenceKey: occurrence.event.reminderOccurrenceKey,
            mode: mode, createdAt: now(), wakeAt: wakeAt
        )
        currentlyShown = nil
        // No sound here, deliberately — snoozing is the user saying "not
        // now," not an event worth chiming about. The reveal sound plays
        // again naturally on reappearance via `apply()`'s `isNewOccurrence`
        // check, since `currentlyShown` is nil in the meantime.
        hidePresented(restoreFocus: true)

        // Exact-deadline reappearance — the minute-aligned scan timer
        // alone would make a short snooze inaccurate by up to ~60s. A
        // `wakeAt` at or before `now()` (meeting starting within the next
        // instant, or already started) still fires promptly rather than
        // being rejected.
        scheduleNextSnoozeExpiry()
    }

    func scheduleNextSnoozeExpiry() {
        snoozeExpiryTimer?.invalidate()
        guard let wakeAt = snoozeStateByOccurrenceID.values.map(\.wakeAt).min() else {
            snoozeExpiryTimer = nil
            return
        }
        let timer = Timer(fire: max(wakeAt, now()), interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        snoozeExpiryTimer = timer
    }

    /// Called by the shared suppression store after a context-menu or Undo
    /// command. A mute cancels any pending reminder for exactly this key.
    func reminderSuppressionChanged(for key: ReminderOccurrenceKey, muted: Bool) {
        if muted {
            snoozeStateByOccurrenceID = snoozeStateByOccurrenceID.filter {
                $0.value.reminderOccurrenceKey != key
            }
            scheduleNextSnoozeExpiry()
            if currentlyShown?.event.reminderOccurrenceKey == key { hideIfShown() }
        }
        refresh()
    }

    func dismiss(_ occurrence: MeetingHUDOccurrence) {
        dismissedOccurrenceIDs.insert(occurrence.id)
        currentlyShown = nil
        hidePresented(restoreFocus: true)
    }

    /// Pruned wholesale on a calendar-day change — simpler and sufficient
    /// here than per-id expiry, since the HUD only ever concerns
    /// *today's* meetings, so yesterday's dismissed/snoozed ids are moot
    /// once the day rolls over. Guards against unbounded growth in a
    /// menu-bar app that can run for weeks.
    func pruneStateIfDayChanged(_ today: Date) {
        guard lastKnownDay != today else { return }
        lastKnownDay = today
        dismissedOccurrenceIDs.removeAll()
        snoozeStateByOccurrenceID.removeAll()
        snoozeExpiryTimer?.invalidate()
        snoozeExpiryTimer = nil
    }
}
