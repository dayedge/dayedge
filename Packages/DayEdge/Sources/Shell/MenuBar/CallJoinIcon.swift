import AppKit
import SwiftUI
import Domain
import UI

/// The menu bar's "join this call" icon — the service's own brand glyph
/// (falling back to a generic camera glyph for a service with no bundled
/// icon). Sits immediately left of `MenuBarBadgeIcon` inside
/// `CombinedMenuBarIcon`, so it matches that icon's *asymmetric*
/// top/bottom canvas padding (more room above than below, reserved there
/// for the badge's "+" overflow) rather than simple symmetric centering —
/// otherwise, even with equal total canvas heights, this icon's centered
/// content would visibly sit higher than the calendar frame's own
/// off-center content next to it.
struct CallJoinIcon: View {
    let service: VideoConferenceService
    var inkColor: Color = .black

    static let width: CGFloat = 16
    private static let contentHeight: CGFloat = 15

    var body: some View {
        Group {
            if let resourceName = service.iconResourceName {
                BrandIcon(resourceName: resourceName)
            } else {
                Image(systemName: "video.fill")
                    .resizable()
                    .scaledToFit()
            }
        }
        .foregroundStyle(inkColor)
        .frame(width: Self.width, height: Self.contentHeight)
        .padding(.top, MenuBarBadgeIcon.topContentInset)
        .padding(.bottom, MenuBarBadgeIcon.bottomContentInset)
    }
}

extension CallJoinIcon {
    /// Renders to an `NSImage` marked as a template — see
    /// `MenuBarBadgeIcon.render(value:cornerBadge:)`, which this mirrors. Kept for
    /// standalone use/testing; `AppDelegate` normally renders this
    /// composed with the badge via `CombinedMenuBarIcon` instead.
    @MainActor
    static func render(service: VideoConferenceService) -> NSImage? {
        let renderer = ImageRenderer(content: CallJoinIcon(service: service))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = true
        return image
    }
}
