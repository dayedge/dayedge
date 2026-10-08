import Foundation
import JavaScriptCore

/// Wraps chrono-node (https://github.com/wanasit/chrono), a small,
/// deterministic, rule-based natural-language date parser — not an LLM —
/// running inside JavaScriptCore, a system framework already present on
/// every Mac. No network access at runtime and no bundled Node runtime:
/// just the ~155KB minified library (`Resources/chrono.js`) evaluated
/// once inside a `JSContext`.
///
/// Deterministic by construction: the same query and reference date
/// always produce the same answer — an on-device LLM stage was tried
/// first and dropped after showing real hallucination risk on the same
/// queries this handles correctly (e.g. inventing an unrelated date for
/// an unsupported input language).
package struct ChronoSearchIntentStage: SearchIntentPipelineStage {
    package let name = "chrono"

    package func resolve(_ text: String, referenceDate: Date, calendar: Calendar) async -> SearchIntent? {
        await ChronoEngine.shared.resolve(text, referenceDate: referenceDate)
    }
}
