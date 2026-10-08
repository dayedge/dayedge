import Foundation

/// One pluggable step in resolving search-bar text into a `SearchIntent`.
/// `SearchIntentPipeline` runs stages in order and uses the first one that
/// recognizes the query — a new source of understanding (the on-device
/// LLM, `NSDataDetector`, a future external LLM API) plugs in by
/// conforming to this and adding itself to a pipeline's stage list, with
/// no changes needed anywhere else.
package protocol SearchIntentPipelineStage: Sendable {
    /// Shown only in diagnostic logging.
    var name: String { get }

    /// Nil means "I don't recognize this" — the pipeline moves on to the
    /// next stage rather than treating that as an error.
    func resolve(_ text: String, referenceDate: Date, calendar: Calendar) async -> SearchIntent?
}
