import SwiftUI
import Domain
import UI

/// The persistent bottom chrome, the same in every view: the contextual
/// selector at the bottom left (calendars in Month/Day, lists in Tasks,
/// chats in Ask — none in the Search view) and Settings at the bottom
/// right. The popover content is supplied by the caller.
///
/// Siblings of the top view switcher, not copies: the same height, capsule,
/// surface family and keyline. Their character comes from placement — the
/// selector starts on the content's left axis, Settings ends on the
/// switcher's right one — never from squarer geometry.
struct FooterBarView<Picker: View>: View {
    @Environment(\.themePalette) private var theme

    /// The selector's summary ("All Calendars", "Work + Home"); nil: no
    /// selector (the Search view).
    let label: String?
    /// What the selector chooses, as an SF Symbol.
    var symbol = "calendar"
    /// Owned by the root so it can pause keyboard shortcuts while open.
    @Binding var isPresented: Bool
    let onSettingsTap: () -> Void
    /// The calendar index filling: a status segment leads the selector.
    var indexActivity: CalendarIndexActivity?
    @ViewBuilder let picker: () -> Picker

    var body: some View {
        HStack(spacing: 0) {
            BottomContextSelector(label: label, symbol: symbol, isPresented: $isPresented,
                                  indexActivity: indexActivity, picker: picker)
            Spacer(minLength: 12)
            SettingsChromeButton(action: onSettingsTap)
        }
        .padding(.leading, AppTheme.horizontalPadding)
        .padding(.trailing, PanelToolbarMetrics.trailingChromeInset)
        // Keep the registered safe-area bar compact: its total height also
        // determines how far upward the system scroll-edge fade begins.
        .padding(.vertical, 4)
        .offset(y: -3)
        // Attached as a floating bar via `.floatingFooterBar` (see
        // `RootView`) rather than sitting in the normal layout
        // flow — no card background of its own, just the two controls.
    }
}

/// The persistent chrome's controls: the view switcher's height, and
/// fully rounded like it — always a capsule.
enum PersistentChromeMetrics {
    static var height: CGFloat { ViewModeSwitcherView.width(folded: true) }
    static let paddingH: CGFloat = 12
    static let symbolToLabel: CGFloat = 6

    static var shape: Capsule { Capsule() }
}

private extension View {
    /// The persistent chrome's surface: the view switcher's family — its
    /// fill, the theme's fine keyline, its elevation — made translucent
    /// over the agenda by the theme's chrome material and tint opacity
    /// (Frost: its own floating-control glass). Only the surface: labels
    /// and glyphs stay fully opaque.
    func persistentChromeSurface(_ theme: ThemePalette, isHovered: Bool = false) -> some View {
        let shape = PersistentChromeMetrics.shape
        let fill = isHovered ? theme.persistentChromeHoverSurface : theme.persistentChromeSurface
        return background {
            ZStack {
                if let material = theme.persistentChromeMaterial {
                    shape.fill(material)
                }
                ThemedSurface(role: .floatingControl, fill: fill.opacity(theme.persistentChromeTintOpacity),
                                shape: shape)
            }
        }
        .overlay {
            if let keyline = theme.persistentChromeKeyline {
                shape.strokeBorder(keyline, lineWidth: 0.5)
            }
        }
        .surfaceElevation(.floatingControl)
    }
}

/// The contextual selector — `[ ▤ All Calendars ▾ ]`. One focus target; a
/// leading status segment joins it while the calendar index fills —
/// `[ ◌ │ ▤ All Calendars ▾ ]` — growing from the anchored left edge.
private struct BottomContextSelector<Picker: View>: View {
    @Environment(\.themePalette) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let label: String?
    let symbol: String
    @Binding var isPresented: Bool
    let indexActivity: CalendarIndexActivity?
    @ViewBuilder let picker: () -> Picker

    @State private var isHovered = false

    private var status: CalendarIndexActivity? {
        indexActivity.flatMap { $0.showsIndicator ? $0 : nil }
    }

    var body: some View {
        HStack(spacing: 0) {
            if let status {
                IndexingStatusSegment(activity: status, side: PersistentChromeMetrics.height)
                    .transition(.opacity)
                if label != nil {
                    Rectangle()
                        .fill(theme.persistentChromeDivider)
                        .frame(width: 1, height: PersistentChromeMetrics.height * 0.45)
                        .transition(.opacity)
                }
            }
            if let label {
                selectorButton(label)
            }
        }
        .frame(height: PersistentChromeMetrics.height)
        .persistentChromeSurface(theme, isHovered: isHovered)
        .opacity(label == nil && status == nil ? 0 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: status != nil)
    }

    private func selectorButton(_ label: String) -> some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: PersistentChromeMetrics.symbolToLabel) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.persistentChromeSecondaryForeground)
                Text(label)
                    .font(AppTheme.TextStyle.footer)
                    .foregroundStyle(theme.primaryText)
                    // A chat's title can be a whole question: no wider
                    // than a calendar or list summary.
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // At most this wide, otherwise just the text's own
                    // width (a bare max-width frame would grow every
                    // selector to it).
                    .frame(maxWidth: 130)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.persistentChromeSecondaryForeground)
            }
            .padding(.horizontal, PersistentChromeMetrics.paddingH)
            .frame(height: PersistentChromeMetrics.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            picker()
        }
        .accessibilityLabel(label)
        .accessibilityHint(L10n.tr("footerbarview.menu", "Menu"))
        .accessibilityValue(status.map(IndexingStatusSegment.accessibilityStatus) ?? "")
    }
}

/// Settings, always at the bottom right: icon-only, the selector's height
/// and capsule (a circle at this size) — the bottom chrome's second member.
private struct SettingsChromeButton: View {
    @Environment(\.themePalette) private var theme
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.primaryText)
                .frame(width: PersistentChromeMetrics.height, height: PersistentChromeMetrics.height)
                .contentShape(PersistentChromeMetrics.shape)
        }
        .buttonStyle(.plain)
        .persistentChromeSurface(theme, isHovered: isHovered)
        .onHover { isHovered = $0 }
        .accessibilityLabel(L10n.tr("footerbarview.settings", "Settings"))
    }
}
