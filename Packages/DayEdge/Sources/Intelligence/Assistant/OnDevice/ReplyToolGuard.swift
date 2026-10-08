import Foundation

/// The tool calls of one on-device reply, kept inside the budget: each
/// result is cut to `limits.toolResult` tokens at whole lines ("…and 12
/// more"), and after `limits.toolCalls` calls a tool answers that there's
/// enough to go on instead of running.
package actor ReplyToolGuard {
    private let limits: ContextBudget.Limits
    private let meter: any TokenMeter
    private var calls = 0

    package init(limits: ContextBudget.Limits, meter: any TokenMeter) {
        self.limits = limits
        self.meter = meter
    }

    package func run(_ call: @Sendable () async throws -> String) async throws -> String {
        calls += 1
        if let most = limits.toolCalls, calls > most {
            return "That's enough data — answer with what you already have."
        }
        return await fit(try await call())
    }

    func fit(_ result: String) async -> String {
        guard let cap = limits.toolResult, await meter.tokens(result) > cap else { return result }
        let lines = result.components(separatedBy: "\n")
        var kept = lines.count
        while kept > 1 {
            kept -= 1
            let candidate = lines.prefix(kept).joined(separator: "\n") + "\n…and \(lines.count - kept) more"
            if await meter.tokens(candidate) <= cap { return candidate }
        }
        return lines.first.map { String($0.prefix(cap)) } ?? ""
    }
}
