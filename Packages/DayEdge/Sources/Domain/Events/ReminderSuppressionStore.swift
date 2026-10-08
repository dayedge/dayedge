import Foundation
import Observation

/// The single source of truth for the app-only reminder muting. The defaults
/// value is a small property-list dictionary of occurrence key to expiry;
/// neither EventKit nor the source calendar is changed.
@MainActor
@Observable
package final class ReminderSuppressionStore {
    package static let storageKey = "reminderSuppression.expirations.v1"
    package static let gracePeriod: TimeInterval = 7 * 24 * 60 * 60
    package static let globalStorageKey = "reminderSuppression.globalUntil.v1"

    package private(set) var expiryByKey: [String: Date]
    /// "Mute Until ›": every the app meeting reminder, until a time. Kept
    /// apart from the per-occurrence mutes, which it outranks while active.
    package private(set) var globalMute: GlobalMute?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored package var onMutation: ((ReminderOccurrenceKey, Bool) -> Void)?
    @ObservationIgnored package var onGlobalMutation: (() -> Void)?

    package struct GlobalMute: Equatable {
        package let until: Date
        /// What the user picked, so the menu can say it back.
        package let chosen: MuteUntilOption?
    }

    package init(defaults: UserDefaults = .standard, now: @escaping () -> Date = { .now }) {
        self.defaults = defaults
        self.now = now
        self.expiryByKey = defaults.dictionary(forKey: Self.storageKey)?
            .compactMapValues { $0 as? Date } ?? [:]
        if let stored = defaults.dictionary(forKey: Self.globalStorageKey),
           let until = stored["until"] as? Date {
            self.globalMute = GlobalMute(until: until, chosen: (stored["chosen"] as? String).flatMap(MuteUntilOption.init(rawValue:)))
        }
        pruneExpired()
    }

    package func isMuted(_ event: AgendaEventModel) -> Bool {
        guard let key = event.reminderOccurrenceKey,
              let expiry = expiryByKey[key.storageKey] else { return false }
        return expiry > now()
    }

    @discardableResult
    package func setMuted(_ muted: Bool, for event: AgendaEventModel) -> Bool {
        guard let key = event.reminderOccurrenceKey, !event.isAllDay,
              let end = event.endDate else { return false }
        pruneExpired()
        let wasMuted = isMuted(event)
        guard wasMuted != muted else { return false }
        if muted {
            expiryByKey[key.storageKey] = max(end, now()).addingTimeInterval(Self.gracePeriod)
        } else {
            expiryByKey[key.storageKey] = nil
        }
        persist()
        onMutation?(key, muted)
        return true
    }

    package var isGloballyMuted: Bool {
        guard let globalMute else { return false }
        return globalMute.until > now()
    }

    /// The active global mute, if any.
    package var activeGlobalMute: GlobalMute? { isGloballyMuted ? globalMute : nil }

    package func muteAll(until: Date, chosen: MuteUntilOption?) {
        globalMute = GlobalMute(until: until, chosen: chosen)
        persistGlobal()
        onGlobalMutation?()
    }

    package func unmuteAll() {
        guard globalMute != nil else { return }
        globalMute = nil
        persistGlobal()
        onGlobalMutation?()
    }

    /// Keep a muted occurrence's expiry attached to its latest known end
    /// after a calendar edit. This never transfers state to a different key.
    package func reconcile(_ events: [AgendaEventModel]) {
        var changed = false
        for event in events {
            guard let key = event.reminderOccurrenceKey, let end = event.endDate,
                  expiryByKey[key.storageKey] != nil else { continue }
            let expiry = end.addingTimeInterval(Self.gracePeriod)
            if let existing = expiryByKey[key.storageKey], expiry > existing {
                expiryByKey[key.storageKey] = expiry
                changed = true
            }
        }
        if changed { persist() }
    }

    package func pruneExpired() {
        let cutoff = now()
        if let globalMute, globalMute.until <= cutoff {
            self.globalMute = nil
            persistGlobal()
        }
        let retained = expiryByKey.filter { $0.value > cutoff }
        guard retained.count != expiryByKey.count else { return }
        expiryByKey = retained
        persist()
    }

    private func persist() {
        defaults.set(expiryByKey, forKey: Self.storageKey)
    }

    private func persistGlobal() {
        guard let globalMute else {
            defaults.removeObject(forKey: Self.globalStorageKey)
            return
        }
        var stored: [String: Any] = ["until": globalMute.until]
        if let chosen = globalMute.chosen { stored["chosen"] = chosen.rawValue }
        defaults.set(stored, forKey: Self.globalStorageKey)
    }
}
