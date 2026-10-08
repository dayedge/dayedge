import Foundation

/// Runs search-bar text through an ordered list of pluggable
/// `SearchIntentPipelineStage`s, stopping at the first one that
/// recognizes it. Falls through to `freeTextSearch` if none do.
package struct SearchIntentPipeline {
    package let stages: [SearchIntentPipelineStage]

    /// Calendar-specific expressions are resolved before Chrono. `NSDataDetector`,
    /// a future external LLM API, or another on-device model each become
    /// an additional `SearchIntentPipelineStage` here later; this is the
    /// one place that changes to add or remove one.
    package static let live = SearchIntentPipeline(stages: [TemporalSearchIntentStage(), ChronoSearchIntentStage()])

    package func resolve(_ text: String, referenceDate: Date = Date(), calendar: Calendar = .autoupdatingCurrent) async -> SearchIntent {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .freeTextSearch("") }

        for stage in stages {
            if let intent = await stage.resolve(trimmed, referenceDate: referenceDate, calendar: calendar) {
                return intent
            }
        }
        return .freeTextSearch(trimmed)
    }
}
