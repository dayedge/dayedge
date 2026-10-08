import Foundation

struct ActiveSlotCandidate<Value> {
    let value: Value
    let start: Date
    let end: Date
}

/// Finds the item whose "ready from `start - leadMinutes` until
/// `min(end, nextStart)`" window contains `now` — shared by
/// `CallReadinessStrategy` (the menu-bar "ready to join" icon) and the
/// Meeting HUD's occurrence resolver, so two back-to-back items hand off
/// identically for both rather than each having its own, potentially
/// slightly different, windowing math.
func resolveActiveSlot<Value>(
    _ candidates: [ActiveSlotCandidate<Value>], now: Date, leadMinutes: Int
) -> Value? {
    let sorted = candidates.sorted { $0.start < $1.start }
    for (index, candidate) in sorted.enumerated() {
        let readyFrom = candidate.start.addingTimeInterval(TimeInterval(-leadMinutes * 60))
        let nextStart = index + 1 < sorted.count ? sorted[index + 1].start : nil
        let readyUntil = min(candidate.end, nextStart ?? .distantFuture)
        if now >= readyFrom, now < readyUntil {
            return candidate.value
        }
    }
    return nil
}
