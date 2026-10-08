import Foundation

/// Fits one on-device reply into the model's window. Every part has a cap,
/// and the caps add up to less than the window:
///
///     fixed (instructions + tools) + question + history + tool results + answer
///         ≤ contextSize × (1 − meter.margin)
///
/// The question, tool results and answer are capped up front; the history
/// gets what's left, newest first, earlier answers shortened. What can still
/// go wrong is only the meter's error — the backend retries once without
/// history for that.
package struct ContextBudget: Sendable {
    package struct Limits: Sendable, Equatable {
        /// Caps in tokens; nil = no cap.
        package var answer: Int?
        package var toolResult: Int?
        package var toolCalls: Int?
        package var question: Int?
        package var earlierAnswer: Int?

        package static let standard = Limits(answer: 400, toolResult: 450, toolCalls: 2, question: 300, earlierAnswer: 120)
        /// Nothing capped — the behaviour before budgeting.
        package static let unlimited = Limits()

        /// What the reply itself may still add: its tool results and answer.
        var reserve: Int { (answer ?? 0) + (toolResult ?? 0) * (toolCalls ?? 0) }
    }

    /// What one reply sends.
    package struct Plan: Sendable {
        package var question: String
        package var history: [ChatMessage]
        package var limits: Limits
    }

    package let meter: any TokenMeter
    package let contextSize: Int
    package let limits: Limits

    package init(meter: any TokenMeter, contextSize: Int, limits: Limits) {
        self.meter = meter
        self.contextSize = contextSize
        self.limits = limits
    }

    /// The meter's budget: measured, capped; the no-op meter caps nothing.
    package static func make(_ choice: TokenMeterChoice, contextSize: Int) -> ContextBudget {
        let meter = TokenMeters.make(choice)
        return ContextBudget(meter: meter, contextSize: contextSize, limits: choice == .none ? .unlimited : .standard)
    }

    package func plan(instructions: String, tools: [AssistantTool], history: some Collection<ChatMessage>,
                      question: String) async -> Plan {
        let usable = Int(Double(contextSize) * (1 - meter.margin))
        let fixed = await meter.tokens(instructions: instructions, tools: tools)
        let shortQuestion = await fit(question, to: limits.question)
        var left = usable - fixed - (await meter.tokens(shortQuestion)) - limits.reserve

        var kept: [ChatMessage] = []
        for message in history.reversed() where message.carriesContext {
            var message = message
            if message.role == .assistant { message.text = await fit(message.text, to: limits.earlierAnswer) }
            let cost = await meter.tokens(message.text)
            guard cost <= left else { break }
            left -= cost
            kept.insert(message, at: 0)
        }
        return Plan(question: shortQuestion, history: kept, limits: limits)
    }

    /// The text cut to `cap` tokens at a sentence (else word) boundary, with
    /// "…" where it was cut; as it is when it fits or there's no cap.
    func fit(_ text: String, to cap: Int?) async -> String {
        guard let cap, await meter.tokens(text) > cap else { return text }
        var cut = Substring(text)
        while !cut.isEmpty, await meter.tokens(String(cut) + "…") > cap {
            let shorter = cut.dropLast(max(1, cut.count / 5))
            let boundary = shorter.lastIndex { ".!?\n".contains($0) } ?? shorter.lastIndex(of: " ")
            cut = boundary.map { shorter[..<$0] } ?? shorter
        }
        return cut.isEmpty ? "" : String(cut) + "…"
    }
}

extension ChatMessage {
    /// Worth sending as history: finished, said something, and not a failure.
    var carriesContext: Bool { !isPending && !isFailure && !text.isEmpty }
}
