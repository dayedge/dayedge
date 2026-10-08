import Foundation
import SwiftUI
import Domain
import UI

/// Lightweight per-occurrence state for the Meeting HUD. The complete
/// display model is retained so the HUD can present the same event-details
/// view as the agenda without fetching EventKit again; `AgendaEventModel`
/// is already a value-only projection and never retains an `EKEvent`.
struct MeetingHUDOccurrence: Equatable, Identifiable {
    /// == `AgendaEventModel.id` — already per-occurrence (pairs
    /// `eventIdentifier` with the occurrence's own start time), so
    /// dismiss/snooze state keyed by this never affects a different
    /// occurrence of the same recurring event.
    let event: AgendaEventModel
    let start: Date
    let end: Date

    var id: String { event.id }
    var title: String { event.title }
    var calendarColor: Color { event.color }
    /// `nil` when there's no useful participant count to show — an
    /// empty attendee list — per the spec's "hide the attendee element"
    /// rule, rather than showing "0".
    var participantCount: Int? { event.attendees.isEmpty ? nil : event.attendees.count }
    var meetingURL: URL? { event.meetingLink?.preferredURL }
    var videoService: VideoConferenceService? { event.videoService }
}

/// Picks at most one occurrence to show, from `events` (assumed to
/// already be exactly one day's — the caller's job, same convention as
/// `CallReadinessStrategy.readyEvent`). Visibility lifetime, explicitly:
/// shown from `resolveActiveSlot`'s window (`start - leadMinutes` until
/// the earlier of the event's own end or the next eligible event's
/// start) until Join, Snooze, Dismiss, the event's own cancellation, or
/// handoff to a newer eligible meeting — the caller (`MeetingHUDController`)
/// is what actually enforces Join/Snooze/Dismiss; this function only
/// answers "what, if anything, is eligible right now."
func resolveMeetingHUDOccurrence(
    events: [AgendaEventModel], now: Date, configuration: MeetingHUDConfiguration
) -> MeetingHUDOccurrence? {
    let eligible = events.filter { event in
        guard event.status != .cancelled, !event.isAllDay,
              let start = event.startDate, let end = event.endDate, start < end else { return false }
        switch configuration.showFor {
        case .meetingsWithLink: return event.meetingLink?.canJoin ?? false
        case .allTimedEvents: return true
        }
    }
    let candidates: [ActiveSlotCandidate<AgendaEventModel>] = eligible.map {
        ActiveSlotCandidate(value: $0, start: $0.startDate!, end: $0.endDate!)
    }
    guard let event = resolveActiveSlot(candidates, now: now, leadMinutes: configuration.leadTimeMinutes) else {
        return nil
    }
    return MeetingHUDOccurrence(
        event: event,
        start: event.startDate!,
        end: event.endDate!
    )
}
