import SwiftUI

/// The whole app as a SwiftUI `App`. The Xcode app target only starts it
/// (`DayEdgeApp.main()`).
public struct DayEdgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    public init() {}

    public var body: some Scene {
        // The real window is created and owned by AppDelegate (see its
        // doc comment) — SwiftUI's own Scene types can't produce the
        // frameless, non-rectangular bubble window the app needs.
        // A required placeholder scene only — the real Settings window is
        // managed directly by AppDelegate (see its doc comment for why).
        Settings {
            EmptyView()
        }
    }
}
