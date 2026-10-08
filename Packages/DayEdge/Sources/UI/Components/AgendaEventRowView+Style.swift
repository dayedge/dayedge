import SwiftUI
import Domain

extension AgendaEventRowView {
    var titleColor: Color {
        switch event.status {
        case .cancelled: return theme.content.cancelledText
        case .tentative: return theme.content.tentativeText
        case .confirmed, .untimed: return theme.primaryText
        }
    }

    var timeColor: Color {
        if isOngoing { return theme.content.ongoingIndicator }
        switch event.status {
        case .cancelled: return theme.content.cancelledMetadata
        case .tentative: return theme.content.tentativeMetadata
        case .confirmed, .untimed: return theme.secondaryText
        }
    }

    var subtitleColor: Color {
        event.status == .tentative ? theme.content.tentativeMetadata : theme.secondaryText
    }

    var rowBackground: Color {
        if isShowingDetail { return theme.content.detailSelectionFill }
        if isKeyboardSelected { return theme.chrome.rowSelection }
        if isHovering { return theme.chrome.rowHover }
        return .clear
    }
}
