import AppKit
import SwiftUI
import Domain

/// A left-to-right, top-to-bottom wrapping layout — used for the Day
/// view's horizontal all-day track, which reads best as a flowing row of
/// tags (wrapping to a new line once they run out of width) rather than
/// one full-width row each.
package struct FlowLayout: Layout {
    package var spacing: CGFloat = 6
    package var lineSpacing: CGFloat = 6

    package func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + lineSpacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    package func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// One all-day event, rendered as a quiet tinted tag rather than a filled
/// capsule — a full-color capsule read too much like a button/selected
/// state; a tinted rounded rect at low opacity plus a faint matching
/// border reads as content (the same "identity via color" idea, just
/// restrained) without competing with real actions like the Join pill.
package struct AllDayEventTagView: View {
    @Environment(\.themePalette) private var theme

    package let event: AgendaEventModel
    package let date: Date
    package var detailPresentationRequest: EventDetailPresentationRequest?
    package var detailActionRequest: EventDetailActionRequest?
    package var onDetailPresentationChange: (Bool) -> Void = { _ in }
    package var onDetailActionFocusChange: (EventDetailFocusableAction?) -> Void = { _ in }
    /// Day view keyboard selection.
    package var isKeyboardSelected = false

    @State private var isShowingDetail = false
    @State private var isHovering = false
    /// Mirrors `AgendaEventRowView`'s same guard: the system's own
    /// outside-click dismissal fires ahead of `onTapGesture`'s mouse-up
    /// recognition, so a click that lands right on the heels of a dismiss
    /// is that same click, not a new one.
    @State private var lastDismissAt: Date = .distantPast

    private static let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

    private var tintOpacity: Double { isHovering ? theme.sourcePresentation.allDayHoverFillOpacity : theme.sourcePresentation.allDayFillOpacity }
    private var borderOpacity: Double { isHovering ? theme.sourcePresentation.allDayHoverBorderOpacity : theme.sourcePresentation.allDayBorderOpacity }

    /// The calendar color itself, at full strength, reads clearly against
    /// the app's near-black background for most hues — but a dark
    /// calendar color (navy, dark purple, brown) doesn't, so those fall
    /// back to a near-white label instead of a low-contrast tinted one.
    private var textColor: Color {
        if theme.isLight { return theme.primaryText }
        guard let rgb = NSColor(event.color).usingColorSpace(.deviceRGB) else { return theme.primaryText }
        let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return luminance > 0.45 ? event.color : theme.content.sourceLabelFallback
    }

    package var body: some View {
        Text(verbatim: event.title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(textColor)
            .lineLimit(1)
            .padding(.horizontal, 11)
            .frame(height: 25)
            .background(Self.shape.fill(event.color.opacity(tintOpacity)))
            .overlay(Self.shape.strokeBorder(event.color.opacity(borderOpacity), lineWidth: 1))
            .overlay {
                if isKeyboardSelected { Self.shape.strokeBorder(theme.chrome.selectionKeyline, lineWidth: 1.5) }
            }
            .contentShape(Self.shape)
            .onHover { isHovering = $0 }
            .popover(isPresented: $isShowingDetail, arrowEdge: .top) {
                EventDetailPopoverView(
                    event: event,
                    date: date,
                    actionRequest: detailActionRequest,
                    onActionFocusChange: onDetailActionFocusChange
                )
            }
            .onChange(of: isShowingDetail) { wasShowing, isShowing in
                if wasShowing, !isShowing {
                    lastDismissAt = Date()
                }
                onDetailPresentationChange(isShowing)
            }
            .onChange(of: detailPresentationRequest) { _, request in
                guard request?.eventID == event.id else { return }
                switch request?.action {
                case .toggle: isShowingDetail.toggle()
                case .dismiss: isShowingDetail = false
                case nil: break
                }
            }
            .onTapGesture {
                guard isShowingDetail else {
                    guard Date().timeIntervalSince(lastDismissAt) > 0.3 else { return }
                    isShowingDetail = true
                    return
                }
                isShowingDetail = false
            }
            .eventContextMenu(for: event)
    }

    package init(
        event: AgendaEventModel,
        date: Date,
        detailPresentationRequest: EventDetailPresentationRequest? = nil,
        detailActionRequest: EventDetailActionRequest? = nil,
        onDetailPresentationChange: @escaping (Bool) -> Void = { _ in },
        onDetailActionFocusChange: @escaping (EventDetailFocusableAction?) -> Void = { _ in },
        isKeyboardSelected: Bool = false
    ) {
        self.event = event
        self.date = date
        self.detailPresentationRequest = detailPresentationRequest
        self.detailActionRequest = detailActionRequest
        self.onDetailPresentationChange = onDetailPresentationChange
        self.onDetailActionFocusChange = onDetailActionFocusChange
        self.isKeyboardSelected = isKeyboardSelected
    }
}
