import CoreGraphics

/// Scrollspy for the Tasks document: which section is "current" given where
/// the visible section headers sit. Pure, so the hysteresis is testable.
///
/// `headerOffsets` are the headers' top edges in the scroll view's space
/// (only headers currently rendered appear). A header at or above
/// `activationLine` has been reached. To avoid flicker with a boundary
/// sitting on the line, the current section only changes once the new
/// candidate has crossed `hysteresis` points past it.
package enum TaskSectionSpy {
    package static func activeSection(
        headerOffsets: [String: CGFloat],
        order: [String],
        current: String?,
        activationLine: CGFloat,
        hysteresis: CGFloat = 12
    ) -> String? {
        let known = order.filter { headerOffsets[$0] != nil }
        guard !known.isEmpty else { return current ?? order.first }

        let reached = known.filter { headerOffsets[$0]! <= activationLine }
        let candidate = reached.last ?? known[0]

        guard let current, let currentOffset = headerOffsets[current],
              let currentIndex = order.firstIndex(of: current),
              let candidateIndex = order.firstIndex(of: candidate) else { return candidate }

        if candidateIndex > currentIndex {
            // Moving forward: the next header must be clearly past the line.
            return headerOffsets[candidate]! <= activationLine - hysteresis ? candidate : current
        }
        if candidateIndex < currentIndex {
            // Moving back: the current header must be clearly below the line.
            return currentOffset >= activationLine + hysteresis ? candidate : current
        }
        return current
    }
}
