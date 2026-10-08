import SwiftUI
import Domain

/// The app's peer views presented as one compact segmented control.
/// The shared capsule establishes the group; a circle marks the active view.
///
/// Folding (Ask, where the composer wants the row): only the active view
/// shows, as the top of a small stack of circles. Hovering unfolds it into
/// the full control — growing leftward, the other views fanning out from
/// behind the active one — and it folds back shortly after the pointer
/// leaves.
package struct ViewModeSwitcherView: View {
    @Environment(\.themePalette) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    package let selectedMode: ViewMode
    package var folds = false
    package let onSelect: (ViewMode) -> Void

    private static let cellSize: CGFloat = 26
    private static let cellSpacing: CGFloat = 2
    private static let inset: CGFloat = 2
    /// The circles peeking out behind a folded control: each one's step
    /// leftward, and how much each is shrunk and faded.
    private static let stackStep: CGFloat = 4
    private static let stackDepth = 2
    /// Pointer gone → folded again: long enough not to flicker when the
    /// pointer brushes past the edge.
    private static let foldDelay: Duration = .milliseconds(300)
    private static let foldedOpacity: Double = 0.8

    /// The control's width, for layouts that leave room for it.
    package static var width: CGFloat { width(folded: false) }

    package static func width(folded: Bool) -> CGFloat {
        let count = folded ? 1 : CGFloat(ViewMode.allCases.count)
        return count * cellSize + (count - 1) * cellSpacing + inset * 2
    }

    @State private var hoveredMode: ViewMode?
    /// The pointer is over a folded control (or just left it).
    @State private var isUnfolded = false
    @State private var foldTask: Task<Void, Never>?

    private var isExpanded: Bool { !folds || isUnfolded }

    package var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(ViewMode.allCases.enumerated()), id: \.element) { index, mode in
                let shows = isExpanded || mode == selectedMode
                cell(mode)
                    // Folded cells take no room: the capsule closes around
                    // the active one.
                    .frame(width: shows ? Self.cellSize : 0, alignment: .center)
                    .padding(.leading, index == 0 || !isExpanded ? 0 : Self.cellSpacing)
                    .opacity(shows ? 1 : 0)
                    .allowsHitTesting(shows)
                    .animation(fanAnimation(for: mode), value: isExpanded)
            }
        }
        .padding(Self.inset)
        .background(
            ThemedSurface(role: .floatingControl, fill: theme.persistentChromeSurface, shape: Capsule(),
                            fallbackMaterial: theme.navigationMaterial)
        )
        .surfaceElevation(.floatingControl)
        .background(alignment: .trailing) { foldedStack }
        // Folded it floats over the composer: a little see-through, so the
        // text running under it still reads.
        .opacity(isExpanded ? 1 : Self.foldedOpacity)
        .animation(.easeOut(duration: 0.15), value: isExpanded)
        .contentShape(Capsule())
        .onHover(perform: hover)
        .onChange(of: folds) { _, folds in if !folds { foldTask?.cancel() } }
    }

    private func cell(_ mode: ViewMode) -> some View {
        Button {
            onSelect(mode)
        } label: {
            Image(systemName: mode.symbolName)
                .font(.system(size: mode.symbolSize, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(mode == selectedMode ? theme.primaryText : theme.secondaryText)
        }
        .buttonStyle(ViewModeSlotButtonStyle(
            cellSize: Self.cellSize,
            isSelected: mode == selectedMode,
            isHovered: hoveredMode == mode
        ))
        .onHover { isHovered in
            hoveredMode = isHovered ? mode : (hoveredMode == mode ? nil : hoveredMode)
        }
        .hoverTooltip(isPresented: hoveredMode == mode, edge: .top) {
            TooltipLabel(
                text: mode.tooltipTitle,
                shortcut: KeyboardShortcutSettings.shared.shortcut(for: .viewMode(mode))?.displayLabel
            )
        }
        .accessibilityLabel(mode.accessibilityLabel)
        .accessibilityAddTraits(mode == selectedMode ? .isSelected : [])
    }

    /// Folded: the other views as circles stacked behind the active one,
    /// peeking out to the left, each smaller and fainter.
    private var foldedStack: some View {
        let size = Self.cellSize + Self.inset * 2
        return ZStack(alignment: .trailing) {
            ForEach((1...Self.stackDepth).reversed(), id: \.self) { depth in
                let step = CGFloat(depth)
                let scale: CGFloat = 1 - 0.08 * step
                let fade: Double = 1 - 0.3 * Double(depth)
                ThemedSurface(role: .floatingControl, fill: theme.controlSurface, shape: Circle(),
                                fallbackMaterial: theme.navigationMaterial)
                    .frame(width: size, height: size)
                    .scaleEffect(scale)
                    .opacity(fade)
                    .offset(x: isExpanded ? 0 : -Self.stackStep * step)
            }
        }
        .opacity(isExpanded ? 0 : 1)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.85),
                   value: isExpanded)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The others fan out from the active view, the nearest first; folding
    /// back, all at once.
    private func fanAnimation(for mode: ViewMode) -> Animation {
        if reduceMotion { return .easeOut(duration: 0.15) }
        let spring = Animation.spring(response: 0.34, dampingFraction: 0.86)
        guard isExpanded,
              let from = ViewMode.allCases.firstIndex(of: selectedMode),
              let to = ViewMode.allCases.firstIndex(of: mode) else { return spring }
        return spring.delay(0.025 * Double(abs(to - from)))
    }

    private func hover(_ inside: Bool) {
        foldTask?.cancel()
        guard folds else { return }
        if inside {
            isUnfolded = true
        } else {
            foldTask = Task {
                try? await Task.sleep(for: Self.foldDelay)
                guard !Task.isCancelled else { return }
                isUnfolded = false
            }
        }
    }

    package init(selectedMode: ViewMode, folds: Bool = false, onSelect: @escaping (ViewMode) -> Void) {
        self.selectedMode = selectedMode
        self.folds = folds
        self.onSelect = onSelect
    }
}

private struct ViewModeSlotButtonStyle: ButtonStyle {
    @Environment(\.themePalette) private var theme

    let cellSize: CGFloat
    let isSelected: Bool
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: cellSize, height: cellSize)
            .contentShape(Rectangle())
            .background {
                ThemedSurface(role: .selectedFloatingControl,
                                fill: backgroundColor(isPressed: configuration.isPressed),
                                shape: Circle(), materialIsActive: isSelected)
                    .frame(width: 24, height: 24)
                    .surfaceElevation(.selectedFloatingControl)
            }
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.14), value: isSelected)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isSelected {
            return (isPressed ? theme.chrome.slotSelectedPressed : theme.chrome.slotSelected)
        }
        if isPressed {
            return theme.chrome.pressedFill
        }
        return isHovered ? theme.chrome.slotHover : .clear
    }
}
