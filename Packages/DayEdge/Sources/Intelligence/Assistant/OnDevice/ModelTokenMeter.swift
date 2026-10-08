#if HAS_MACOS26_4_SDK
import Foundation
import FoundationModels

/// The model's own count (`tokenCount`, macOS 26.4+). Counts are cached by
/// text — finished messages and the fixed part are measured once — and a
/// count that fails falls back to the estimate, so measuring never fails a
/// reply.
@available(macOS 26.4, *)
package struct ModelTokenMeter: TokenMeter {
    private let cache = TokenCountCache()
    private let fallback = EstimatingTokenMeter()

    package var name: String { "model" }
    package var margin: Double { 0.03 }

    package func tokens(_ text: String) async -> Int {
        await cache.value(for: text) {
            if let exact = try? await SystemLanguageModel.default.tokenCount(for: text) { return exact }
            return await fallback.tokens(text)
        }
    }

    package func tokens(instructions: String, tools: [AssistantTool]) async -> Int {
        let key = instructions + "\u{1F}" + tools.map(\.name).joined(separator: ",")
        return await cache.value(for: key) {
            let model = SystemLanguageModel.default
            guard let adapted = try? tools.map({ try FoundationModelsTool($0) }),
                  let forInstructions = try? await model.tokenCount(for: Instructions(instructions)),
                  let forTools = try? await model.tokenCount(for: adapted) else {
                return await fallback.tokens(instructions: instructions, tools: tools)
            }
            return forInstructions + forTools
        }
    }
}

/// Counts by text, bounded (cleared when full — they're cheap to redo).
private actor TokenCountCache {
    private var counts: [String: Int] = [:]

    func value(for key: String, count: () async -> Int) async -> Int {
        if let known = counts[key] { return known }
        let value = await count()
        if counts.count > 500 { counts.removeAll() }
        counts[key] = value
        return value
    }
}
#endif
