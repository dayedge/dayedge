import Foundation
import Domain
import UI

/// The one path every change takes: ask (the card, or "always allow"),
/// perform, record the receipt with its Undo, and tell the model exactly
/// what happened — it reports only that.
package enum ChangeRunner {
    package struct Performed: Sendable {
        /// The receipt's line: "Created “Faktura”".
        package let text: String
        package var detail: String?
        package var undo: (@Sendable () async throws -> Void)?
        /// What the model reads.
        package let report: String
    }

    package static func run(
        _ proposal: ChangeProposal,
        context: AssistantToolContext,
        perform: @escaping @Sendable () async throws -> Performed
    ) async -> String {
        guard let approvals = context.approvals else { return "Changes aren't available here." }
        switch await approvals.request(proposal) {
        case .deny:
            await approvals.record(ChatChangeReceipt(
                kind: proposal.kind, text: proposal.kind.declinedReceipt(subject: proposal.subject.title), state: .declined
            ), undo: nil)
            return "The user declined this change; nothing was changed. Don't try it again — ask what they'd like instead."
        case .cancelled:
            return "Cancelled; nothing was changed."
        case .allow, .alwaysAllow:
            do {
                let done = try await perform()
                await approvals.record(ChatChangeReceipt(
                    kind: proposal.kind, text: done.text, detail: done.detail, state: .done
                ), undo: done.undo)
                return done.report
            } catch {
                let message = AssistantChangeFailure.message(error)
                let displayMessage = AssistantChangeFailure.displayMessage(error)
                await approvals.record(ChatChangeReceipt(
                    kind: proposal.kind, text: proposal.kind.failedReceipt(subject: proposal.subject.title),
                    detail: displayMessage, state: .failed(displayMessage)
                ), undo: nil)
                return "That didn't work: \(message). Nothing was changed."
            }
        }
    }

    // How cards and receipts write times: `ChangeText`.
    package static func when(_ date: Date, hasTime: Bool, now: Date, calendar: Calendar,
                             format: TimeFormat = .twentyFourHour, locale: Locale = AppLocalization.displayLocale) -> String {
        ChangeText.when(date, hasTime: hasTime, now: now, calendar: calendar, format: format, locale: locale)
    }

    package static func span(start: Date, end: Date, isAllDay: Bool, now: Date, calendar: Calendar,
                             format: TimeFormat = .twentyFourHour, locale: Locale = AppLocalization.displayLocale) -> String {
        ChangeText.span(start: start, end: end, isAllDay: isAllDay, now: now, calendar: calendar, format: format, locale: locale)
    }

    package static func joined(_ parts: String?...) -> String? { ChangeText.joined(parts) }
}
