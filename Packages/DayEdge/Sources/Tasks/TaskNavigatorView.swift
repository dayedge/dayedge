import AppKit
import SwiftUI
import UI

/// The list navigator under the Tasks title: one chip per landmark section
/// (Attention, each list, Completed). Chips are navigation, not filters — a
/// click scrolls the document there. It is a native horizontal scroll rail:
/// no scrollbar, trackpad/Magic Mouse gestures, faded edges where more
/// chips continue, and the active chip is always brought into view.
package struct TaskNavigatorView: View {
    @Environment(\.themePalette) private var theme

    package typealias Item = TaskNavigatorItem

    package let items: [Item]
    package let activeID: String?
    /// Space after the last chip (smaller when a control follows the rail).
    package var trailingInset: CGFloat = AppTheme.horizontalPadding
    package let onSelect: (String) -> Void

    private struct RailMetrics: Equatable {
        var offset: CGFloat = 0
        var content: CGFloat = 0
        var container: CGFloat = 0
        var canScrollBack: Bool { offset > 1 }
        var canScrollForward: Bool { offset + container < content - 1 }
    }

    @State private var rail = RailMetrics()
    @State private var position = ScrollPosition()
    private static let fadeWidth: CGFloat = 22

    package var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(items) { item in
                        // The id sits on the padded slot, so revealing it
                        // leaves a comfortable margin around the chip.
                        chip(item)
                            .padding(.horizontal, 2)
                            .id(item.id)
                    }
                }
                .padding(.leading, AppTheme.horizontalPadding - 2)
                .padding(.trailing, max(trailingInset - 2, 0))
            }
            .scrollPosition($position)
            // A plain mouse wheel has no horizontal axis: over the rail, let
            // it scroll sideways. (Trackpads and Magic Mouse already do.)
            .background(WheelToHorizontalScroll { delta in scrollRail(by: delta) })
            .onScrollGeometryChange(for: RailMetrics.self) { geometry in
                RailMetrics(
                    offset: geometry.contentOffset.x,
                    content: geometry.contentSize.width,
                    container: geometry.containerSize.width
                )
            } action: { _, metrics in
                rail = metrics
            }
            .mask(edgeFade)
            .onChange(of: activeID) { _, id in
                guard let id else { return }
                // No anchor: scroll only as far as needed to reveal it.
                withAnimation(.smooth(duration: 0.25)) { proxy.scrollTo(id) }
            }
        }
        .frame(height: AppTheme.Tasks.navigatorHeight)
    }

    private func scrollRail(by wheelDelta: CGFloat) {
        let maxOffset = max(rail.content - rail.container, 0)
        let target = min(max(rail.offset - wheelDelta * Self.wheelStep, 0), maxOffset)
        withAnimation(.smooth(duration: 0.12)) { position.scrollTo(x: target) }
    }

    /// Points per wheel unit.
    private static let wheelStep: CGFloat = 36

    /// Fades an edge only while chips continue beyond it.
    private var edgeFade: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [rail.canScrollBack ? .clear : .black, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: Self.fadeWidth)
            Rectangle().fill(.black)
            LinearGradient(colors: [.black, rail.canScrollForward ? .clear : .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: Self.fadeWidth)
        }
    }

    private func chip(_ item: Item) -> some View {
        let isActive = item.id == activeID
        return Button { onSelect(item.id) } label: {
            HStack(spacing: 4) {
                marker(for: item)
                Text(verbatim: item.title)
                    .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? theme.primaryText : theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                // A small, calm count pill — neutral in every state, never
                // the list's color, and kept visible when the name truncates.
                Text("\(item.count)")
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 5)
                    .frame(minWidth: 16, minHeight: 15)
                    .background(Capsule().fill((isActive ? theme.chrome.divider : theme.chrome.slotHover)))
                    .layoutPriority(1)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: 200)
            .frame(height: 24)
            .background(ThemedSurface(role: .selectedNavigation,
                                       fill: isActive ? theme.secondaryControl.pressed : .clear,
                                       shape: Capsule(), materialIsActive: isActive))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    @ViewBuilder
    private func marker(for item: Item) -> some View {
        if let symbol = item.symbol {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(theme.secondaryText)
        } else {
            Circle()
                .fill(item.isAttention ? theme.tasks.attentionTint : (item.color ?? theme.secondaryText))
                .frame(width: 6, height: 6)
        }
    }
}

/// Turns vertical wheel movement over its bounds into a horizontal delta.
/// Only classic wheels (no precise deltas) are handled; trackpads and Magic
/// Mouse scroll the rail natively, and wheel events elsewhere pass through.
private struct WheelToHorizontalScroll: NSViewRepresentable {
    let onDelta: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.hostView = view
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onDelta = onDelta
    }

    func makeCoordinator() -> Coordinator { Coordinator(onDelta: onDelta) }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        weak var hostView: NSView?
        var onDelta: (CGFloat) -> Void
        private var monitor: Any?

        init(onDelta: @escaping (CGFloat) -> Void) { self.onDelta = onDelta }

        func installMonitor() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let view = self.hostView, event.window === view.window,
                      !event.hasPreciseScrollingDeltas,
                      abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
                      view.bounds.contains(view.convert(event.locationInWindow, from: nil)) else { return event }
                self.onDelta(event.scrollingDeltaY)
                return nil
            }
        }

        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
