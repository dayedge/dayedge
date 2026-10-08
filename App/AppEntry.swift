import Shell
import SwiftUI

/// The app: everything lives in the `Shell` module of `Packages/DayEdge`;
/// this target only starts it and carries what makes it an app — the icon
/// (`Assets.xcassets`), `Info.plist` and the entitlements.
@main
enum AppEntry {
    static func main() {
        DayEdgeApp.main()
    }
}
