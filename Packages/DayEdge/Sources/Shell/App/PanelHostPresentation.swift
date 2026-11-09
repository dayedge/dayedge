import Foundation
import Observation

/// One host window's own presence — the Command Window's: whether it's
/// open (from the moment it starts opening, so its views mount and settle
/// before it shows; they don't exist while it's hidden), and each reveal
/// (its command bar takes focus then). The shared
/// `PopoverPresentationCoordinator` says the panel is open; this says
/// which window it's in.
@MainActor
@Observable
final class PanelHostPresentation {
    var isPresented = false
    private(set) var revealID = UUID()

    func didReveal() {
        revealID = UUID()
    }
}
