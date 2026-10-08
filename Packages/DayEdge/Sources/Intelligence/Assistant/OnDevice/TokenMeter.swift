import Foundation

/// Measures how much of the on-device model's context window text takes.
/// The budget (`ContextBudget`) only ever asks a meter — which meter is the
/// one choice (`TokenMeters.make`), so nothing else branches on the OS.
package protocol TokenMeter: Sendable {
    /// "model", "estimate" or "none" — for comparing and tests.
    var name: String { get }
    /// The share of the window kept free for the meter's own error.
    var margin: Double { get }
    func tokens(_ text: String) async -> Int
    /// Instructions plus every tool's definition, as the model receives them.
    func tokens(instructions: String, tools: [AssistantTool]) async -> Int
}

/// Measures nothing: no history is dropped and nothing is cut — the
/// behaviour before budgeting, kept to compare against.
package struct NoOpTokenMeter: TokenMeter {
    package init() {}
    package var name: String { "none" }
    package var margin: Double { 0 }
    package func tokens(_ text: String) async -> Int { 0 }
    package func tokens(instructions: String, tools: [AssistantTool]) async -> Int { 0 }
}

/// A deliberate over-estimate for macOS before 26.4 (no `tokenCount`): one
/// token per three characters — English and calendar text run nearer four —
/// and tool definitions counted as the JSON schema the model reads.
package struct EstimatingTokenMeter: TokenMeter {
    package init() {}
    package var name: String { "estimate" }
    package var margin: Double { 0.10 }

    package func tokens(_ text: String) async -> Int { Self.estimate(text.count) }

    package func tokens(instructions: String, tools: [AssistantTool]) async -> Int {
        Self.estimate(instructions.count + tools.map(Self.definitionLength).reduce(0, +))
    }

    static func estimate(_ characters: Int) -> Int { (characters + 2) / 3 }

    /// A tool as the model sees it: its JSON schema repeats the name and
    /// description, and each parameter and choice brings its own structure
    /// (fitted to — and never below — the schema FoundationModels builds;
    /// `EstimateCalibrationTests` keeps it so).
    static func definitionLength(_ tool: AssistantTool) -> Int {
        var length = 2 * (tool.name.count + tool.description.count) + 130
        for parameter in tool.parameters {
            length += parameter.name.count + parameter.description.count + 55
            for choice in parameter.enumValues ?? [] { length += choice.count + 40 }
        }
        return length
    }
}

/// Which meter measures the on-device context. `automatic`: exact where
/// macOS has `tokenCount` (26.4+), the estimate elsewhere. Hidden, for
/// comparing: `defaults write com.dayedge.app com.dayedge.assistant.tokenMeter none`.
package enum TokenMeterChoice: String, Sendable {
    case automatic, model, estimate, none

    package static let defaultsKey = "com.dayedge.assistant.tokenMeter"

    package static func stored(in defaults: UserDefaults = .standard) -> TokenMeterChoice {
        defaults.string(forKey: defaultsKey).flatMap(TokenMeterChoice.init(rawValue:)) ?? .automatic
    }
}

package enum TokenMeters {
    /// The one place that knows which meters this Mac has.
    package static func make(_ choice: TokenMeterChoice) -> any TokenMeter {
        switch choice {
        case .none: return NoOpTokenMeter()
        case .estimate: return EstimatingTokenMeter()
        case .automatic, .model: return exact ?? EstimatingTokenMeter()
        }
    }

    /// The model's own count, where macOS and the SDK have it.
    private static var exact: (any TokenMeter)? {
        #if HAS_MACOS26_4_SDK
        if #available(macOS 26.4, *) { return ModelTokenMeter() }
        #endif
        return nil
    }
}
