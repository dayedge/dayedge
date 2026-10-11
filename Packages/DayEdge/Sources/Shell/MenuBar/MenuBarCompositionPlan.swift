import Foundation
import Domain

struct MenuBarPrimaryPresentation {
    let badge: MenuBarBadgeContent
    let cornerGlyph: MenuBarCornerGlyph?
    let text: String
    let showsIcon: Bool
    let meeting: MenuBarMeetingPresentation?
}

struct MenuBarCompositionPlan {
    let primary: MenuBarPrimaryPresentation
    let meeting: MenuBarMeetingPresentation?
}

enum MenuBarCompositionStrategy {
    case combined, separate

    init(presentation: MenuBarItemPresentation) {
        switch presentation {
        case .icon: self = .combined
        case .dateTime, .iconAndDateTime: self = .separate
        }
    }

    func plan(configuration: MenuBarDateTimeConfiguration, badge: MenuBarBadgeContent,
              cornerGlyph: MenuBarCornerGlyph?, text: String,
              meeting: MenuBarMeetingPresentation?) -> MenuBarCompositionPlan {
        let inline: MenuBarMeetingPresentation?
        let independent: MenuBarMeetingPresentation?
        switch self {
        case .combined:
            inline = meeting
            independent = nil
        case .separate:
            inline = nil
            independent = meeting
        }
        return MenuBarCompositionPlan(
            primary: MenuBarPrimaryPresentation(
                badge: badge, cornerGlyph: cornerGlyph, text: text,
                showsIcon: configuration.presentation.showsIcon, meeting: inline
            ),
            meeting: independent
        )
    }
}

/// Geometry comes from the status button's actual image/title placement.
struct MenuBarPrimaryGeometry {
    let imageRect: CGRect
    let titleRect: CGRect
    let badgeWidth: CGFloat
    let hasCallIcon: Bool

    var calendarCenterX: CGFloat { imageRect.minX + badgeWidth / 2 }

    func isMeetingHit(_ point: CGPoint) -> Bool {
        if hasCallIcon {
            return imageRect.contains(point) && point.x >= imageRect.minX + badgeWidth
        }
        return titleRect.contains(point)
    }
}
