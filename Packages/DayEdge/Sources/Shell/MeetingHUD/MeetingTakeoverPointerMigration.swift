import CoreGraphics
import Foundation

/// Debounces control migration at screen boundaries without involving AppKit
/// windows or the reminder controller. One instance lives only while visible.
struct MeetingTakeoverPointerMigration {
    private var candidateID: CGDirectDisplayID?
    private var candidateSince: Date?
    private let dwell: TimeInterval = 0.2

    mutating func nextActiveDisplayID(
        currentID: CGDirectDisplayID,
        pointerID: CGDirectDisplayID,
        isClearlyInside: Bool,
        now: Date
    ) -> CGDirectDisplayID? {
        guard isClearlyInside, pointerID != currentID else {
            candidateID = nil
            candidateSince = nil
            return nil
        }
        guard candidateID == pointerID, let candidateSince else {
            candidateID = pointerID
            self.candidateSince = now
            return nil
        }
        guard now.timeIntervalSince(candidateSince) >= dwell else { return nil }
        candidateID = nil
        self.candidateSince = nil
        return pointerID
    }
}
