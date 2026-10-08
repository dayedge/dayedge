import Foundation
import Observation
import UI

/// Lets other parts of the app open Settings on a specific pane (the
/// selectors' "Manage…" footers). The window's own sidebar remains the
/// source of truth once it has applied a request.
@MainActor
@Observable
final class SettingsRouter {
    struct Request: Equatable {
        let id = UUID()
        let pane: SettingsDestination
    }

    private(set) var request: Request?

    func open(_ pane: SettingsDestination) { request = Request(pane: pane) }
}
