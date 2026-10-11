import AppKit
import SwiftUI
import Domain
import UI

/// Service glyph for the independent meeting status item.
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
    @MainActor
    static func render(service: VideoConferenceService, scale: CGFloat = 2) -> NSImage? {
        let renderer = ImageRenderer(content: CallJoinIcon(service: service))
        renderer.scale = scale
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = true
        return image
    }
}
