import Foundation
import Observation

/// One conversation's approvals. A change tool asks here and waits; the
/// card in the chat answers. Nothing is changed without an answer —
/// stopping the reply or leaving the conversation answers `.cancelled`.
@MainActor
@Observable
package final class ChatApprovals {
    package init() {}

    /// The change waiting for the user, shown as the card.
    package private(set) var pending: ChangeProposal?

    @ObservationIgnored private var continuation: CheckedContinuation<ApprovalDecision, Never>?
    @ObservationIgnored private var undos: [UUID: @Sendable () async throws -> Void] = [:]

    /// Kinds the user always allows — Settings, through the root view.
    @ObservationIgnored package var isAlwaysAllowed: (ChangeKind) -> Bool = { _ in false }
    @ObservationIgnored package var rememberAlwaysAllowed: (ChangeKind) -> Void = { _ in }
    /// A change happened (or was declined): the session adds it to the reply.
    @ObservationIgnored package var onReceipt: (ChatChangeReceipt) -> Void = { _ in }
    /// A receipt changed later (Undo).
    @ObservationIgnored package var onReceiptChange: (ChatChangeReceipt) -> Void = { _ in }

    /// Asks the user, unless they always allow this kind (remote models,
    /// never deletions).
    package func request(_ proposal: ChangeProposal) async -> ApprovalDecision {
        if proposal.offersAlwaysAllow, !proposal.kind.isDestructive, isAlwaysAllowed(proposal.kind) {
            return .allow
        }
        decide(.cancelled) // never two cards
        if Task.isCancelled { return .cancelled }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                self.pending = proposal
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.decide(.cancelled) }
        }
    }

    /// The card's buttons, Return / Esc, Stop.
    package func decide(_ decision: ApprovalDecision) {
        guard let continuation else { return }
        if decision == .alwaysAllow, let kind = pending?.kind, !kind.isDestructive {
            rememberAlwaysAllowed(kind)
        }
        self.continuation = nil
        pending = nil
        continuation.resume(returning: decision)
    }

    package func record(_ receipt: ChatChangeReceipt, undo: (@Sendable () async throws -> Void)?) {
        var receipt = receipt
        receipt.canUndo = undo != nil && receipt.state == .done
        if let undo, receipt.canUndo { undos[receipt.id] = undo }
        onReceipt(receipt)
    }

    /// One-shot: the receipt then reads "Undone" (or why it couldn't).
    package func undo(_ receipt: ChatChangeReceipt) async {
        guard let undo = undos.removeValue(forKey: receipt.id) else { return }
        var changed = receipt
        changed.canUndo = false
        do {
            try await undo()
            changed.state = .undone
        } catch {
            changed.state = .failed(L10n.tr("chatapprovals.couldn.t.undo", "Couldn't undo: \(String(describing: AssistantChangeFailure.message(error)))"))
        }
        onReceiptChange(changed)
    }
}
