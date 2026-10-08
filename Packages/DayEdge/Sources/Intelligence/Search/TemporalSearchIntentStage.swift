import Foundation

/// One pipeline stage: normalization is an implementation detail of the
/// complete-expression parser, never a rewrite of Chrono or event-search text.
package struct TemporalSearchIntentStage: SearchIntentPipelineStage {
    package let name = "temporal"
    private let normalizer: TemporalQueryNormalizer
    private static let queue = DispatchQueue(label: "com.dayedge.temporal-normalization")

    package init(normalizer: TemporalQueryNormalizer = .init()) {
        self.normalizer = normalizer
    }

    package func resolve(_ text: String, referenceDate: Date, calendar: Calendar) async -> SearchIntent? {
        await withCheckedContinuation { continuation in
            Self.queue.async {
                let normalized = normalizer.normalize(text)
                let intent = TemporalIntentParser().resolve(
                    normalized.normalized, referenceDate: referenceDate, calendar: calendar
                )
                continuation.resume(returning: intent)
            }
        }
    }
}
