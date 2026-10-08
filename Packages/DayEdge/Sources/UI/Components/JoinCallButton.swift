import AppKit
import SwiftUI

/// Video-call actions shown in the detailed event popover. The service
/// identity is static; copying and joining are deliberately separate hit
/// targets so clicking the link affordance can never accidentally launch
/// the meeting.
package struct JoinCallButton: View {
    @Environment(\.themePalette) private var theme

    package let link: MeetingLink
    package var actionFocus: FocusState<EventDetailFocusableAction?>.Binding
    package var actionRequest: EventDetailActionRequest?

    @State private var isHoveringCopy = false
    @State private var isHoveringJoin = false
    @State private var didCopy = false

    package var body: some View {
        HStack(spacing: 8) {
            iconView
                .frame(width: 14, height: 14)

            Text(link.service.displayName)
                .font(.system(size: 12))
                .foregroundStyle(theme.primaryText)

            Spacer(minLength: 8)

            if let webURL = link.webURL {
                copyButton(webURL)
            }

            if let destination = link.preferredURL {
                joinButton(destination)
            }
        }
        .padding(.vertical, link.canJoin ? 2 : 0)
        .onChange(of: actionRequest) { _, request in
            guard let request else { return }
            switch request.action {
            case .copyLink:
                if let webURL = link.webURL { copy(webURL) }
            case .join:
                if let destination = link.preferredURL { join(destination) }
            case .toggleNotes:
                break
            }
        }
    }

    private func copyButton(_ url: URL) -> some View {
        Button {
            copy(url)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                Text(didCopy ? L10n.tr("joincallbutton.copied", "Copied") : L10n.tr("joincallbutton.copy.link", "Copy Link"))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(didCopy ? theme.controlAccent : theme.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(theme.compactActionFill(isHovered: isHoveringCopy)))
            .compactControlKeyline(theme, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focused(actionFocus, equals: .copyLink)
        .onHover { isHoveringCopy = $0 }
        .help(didCopy ? L10n.tr("joincallbutton.meeting.link.copied", "Meeting link copied") : L10n.tr("joincallbutton.copy.meeting.link", "Copy meeting link"))
        .accessibilityLabel(L10n.tr("joincallbutton.copy.meeting.link.649227", "Copy Meeting Link"))
    }

    private func joinButton(_ destination: URL) -> some View {
        Button {
            join(destination)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "phone.fill")
                Text(L10n.tr("joincallbutton.join", "Join"))
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isHoveringJoin ? theme.onAccentText : link.service.tintColor(theme: theme))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(
                    isHoveringJoin ? link.service.tintColor(theme: theme) : link.service.tintColor(theme: theme).opacity(theme.sourcePresentation.joinFillOpacity)
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focused(actionFocus, equals: .join)
        .onHover { isHoveringJoin = $0 }
        .help(L10n.tr("joincallbutton.join.09c8d1", "Join \(String(describing: link.service.displayName))"))
        .accessibilityLabel(L10n.tr("joincallbutton.join.09c8d1", "Join \(String(describing: link.service.displayName))"))
    }

    private func copy(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            didCopy = false
        }
    }

    private func join(_ destination: URL) {
        NSWorkspace.shared.open(destination)
    }

    @ViewBuilder
    private var iconView: some View {
        if let resourceName = link.service.iconResourceName {
            BrandIcon(resourceName: resourceName)
                .foregroundStyle(theme.secondaryText)
        } else {
            Image(systemName: "video.fill")
                .font(.system(size: 11))
                .foregroundStyle(theme.secondaryText)
        }
    }
}
