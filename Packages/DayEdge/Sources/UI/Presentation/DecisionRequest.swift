import Foundation
import Domain

/// "the app needs a decision before it can continue." One semantic request,
/// shown as a `DecisionCard` — inline in an Ask conversation, or docked at
/// the bottom of the panel everywhere else. Not for acknowledgements (that's
/// a `TransientNotice`: something already happened, with Undo), and not for
/// reversible actions (those just happen, with Undo).
package struct DecisionRequest: Identifiable {
    package enum Kind: Equatable {
        /// May the app do this? (Ask's changes.)
        case permission
        /// Which of several safe options? (A repeating event's scope.)
        case choice
        /// Something that can't be taken back.
        case destructive
    }

    package let id = UUID()
    package let kind: Kind
    /// "Repeating Event", "Delete “Standup”?".
    package let title: String
    /// One line: "Apply this change to:", "Anna won't be notified."
    package var message: String?
    /// A small symbol before the title ("arrow.triangle.2.circlepath").
    package var symbol: String?
    /// The object it's about, drawn the way the Ask card draws it.
    package var subject: ChangeSubject?
    /// In order, left to right. Exactly one should have the `.cancel` role.
    package let actions: [DecisionAction]
    /// What ↩ does when the card appears. Never a destructive action — for a
    /// destructive card ↩ starts on Cancel, so nothing is lost by accident.
    package var defaultActionID: DecisionAction.ID?

    package var cancelAction: DecisionAction? { actions.first { $0.role == .cancel } }
    package var defaultAction: DecisionAction? {
        guard let action = actions.first(where: { $0.id == defaultActionID }), action.role != .destructive else {
            return cancelAction
        }
        return action
    }
}

package struct DecisionAction: Identifiable {
    package enum Role: Equatable { case normal, cancel, destructive }

    package let id = UUID()
    package let title: String
    package var role: Role = .normal
    /// Other versions of this choice, in its ▾ menu (a split button — like
    /// Ask's Allow ▾): "Delete This Event ▾" → "Delete This & Future Events".
    package var alternatives: [DecisionAction] = []
    package let handler: @MainActor () -> Void
}

extension DecisionRequest {
    /// A repeating event's scope: Cancel · [Change This Event ▾] with "This &
    /// Future Events" in the menu — the narrowest scope up front and on ↩.
    /// Deleting makes it destructive (red, and ↩ stays on Cancel).
    package static func eventSpan(message: String, subject: ChangeSubject?, isDeleting: Bool,
                                  onChoose: @escaping @MainActor (EventSpan?) -> Void) -> DecisionRequest {
        let role: DecisionAction.Role = isDeleting ? .destructive : .normal
        let verb = isDeleting ? L10n.tr("decisionrequest.delete", "Delete") : L10n.tr("decisionrequest.change", "Change")
        let thisEvent = DecisionAction(
            title: L10n.tr("decisionrequest.this.event", "\(String(describing: verb)) This Event"), role: role,
            alternatives: [DecisionAction(title: L10n.tr(
                "decisionrequest.this.future.events", "\(String(describing: verb)) This & Future Events"
            ), role: role) { onChoose(.futureEvents) }]
        ) { onChoose(.thisEvent) }
        return DecisionRequest(
            kind: isDeleting ? .destructive : .choice,
            title: L10n.tr("decisionrequest.repeating.event", "Repeating Event"),
            message: message,
            symbol: "arrow.triangle.2.circlepath",
            subject: subject,
            actions: [DecisionAction(title: L10n.tr("decisionrequest.cancel", "Cancel"), role: .cancel) { onChoose(nil) }, thisEvent],
            defaultActionID: thisEvent.id
        )
    }
}
