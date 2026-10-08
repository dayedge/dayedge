import SwiftUI
import Domain
import UI

/// The app's palette: a plain flat field when empty, expanding into one
/// continuous elevated surface — the query row, then the actions it can
/// run (Go to a date, Create a task, Search — with a three-result preview —
/// and Ask). What a query means, and what each key does, is
/// `SearchPaletteModel`'s; this view only draws it. The interpretation is
/// always visible before Enter runs anything.
package struct SearchBarView: View {
    @Environment(\.themePalette) var theme

    @Binding package var query: String
    package var searchFocus: FocusState<Bool>.Binding
    package let palette: SearchPaletteModel
    /// Opens task details from search results (its own, like chat's).
    package var taskCoordinator: CalendarTaskCoordinator?

    /// Which Quick Add field has keyboard focus — an explicit order that Tab
    /// walks (menus aren't in the system's key loop without Full Keyboard
    /// Access, so it isn't left to default traversal).
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @FocusState var quickAddFocus: QuickAddField?

    /// The Search row's one, fixed height — used in BOTH collapsed and
    /// expanded states (also read by `RootView` to reserve
    /// equivalent top padding for the content below, since the expanded
    /// surface is drawn as a sibling overlay that must not push that
    /// content down or resize the popup). Never varies with `isExpanded`:
    /// the whole point of this surface is that Search itself never moves
    /// or resizes when it appears — only the rounded background and the
    /// result row grow around/below it.
    package static let headerHeight: CGFloat = PanelToolbarMetrics.height
    /// How far *below its old resting spot* the whole row (collapsed or
    /// expanded — the two are no longer offset relative to each other at
    /// all) now sits — read by `RootView`, which applies this both
    /// to this view's own top padding and to the reserved space above the
    /// calendar content below it, so the calendar shifts down by the same
    /// amount and the gap between Search and the calendar stays exactly
    /// what it was before this shift.
    ///
    /// This is one of the values that together are the explicit target
    /// geometry — set once, deliberately, rather than tweaked
    /// independently by eye:
    ///   top inset:          15pt (`pointerHeight` (9, default) + this) — unchanged this pass
    ///   left/right inset:    9pt (`surfaceHorizontalInset`)
    ///   omnibox radius:     17pt (`surfaceCornerRadius`) — unchanged this pass
    ///   selected row inset:  9pt (gap folded into `suggestionRowHorizontalInset`)
    ///   selected row radius: 12pt (`suggestionRowCornerRadius`)
    package static let verticalOffset: CGFloat = PanelToolbarMetrics.topInset
    /// The palette's result geometry: every row puts its icon in a fixed
    /// column and its text at one x, so the selected surface, the quiet
    /// placeholder rows and the expanded Quick Add all line up.
    static let suggestionRowCornerRadius: CGFloat = 12
    static let rowInsetH: CGFloat = 12
    static let rowInsetV: CGFloat = 10
    static let iconColumn: CGFloat = 18
    static let iconToText: CGFloat = 10
    static let rowSpacing: CGFloat = 4
    static let placeholderRowHeight: CGFloat = 30
    static let footerInsetBottom: CGFloat = 9
    /// Whitespace, not a line, sets the key footer apart from the results.
    static let footerInsetTop: CGFloat = 5
    static let footerHintSpacing: CGFloat = 12
    /// This view itself has no outer horizontal padding (it sits flush
    /// with the popup's own content edge — see `surfaceHorizontalInset`
    /// below for where the *visible* inset actually comes from), so this
    /// is an absolute position, not a relative gap: the result bubble's
    /// left edge ends up at `surfaceHorizontalInset` + the desired
    /// surface-to-bubble gap (9) from the popup edge.
    static let suggestionRowHorizontalInset: CGFloat = surfaceHorizontalInset + 9
    private static let suggestionRowTopGap: CGFloat = 8
    private static let suggestionRowBottomInset: CGFloat = 4
    package static let surfaceCornerRadius = PanelFieldSurface.cornerRadius
    /// How far the *visible surface* sits in from the popup's own content
    /// edge, on the left and right — deliberately much smaller than the
    /// content's own ~18pt inset (`AppTheme.horizontalPadding`,
    /// applied only inside `headerRow`, never here): the background is
    /// inset independently of that content padding, not nested inside it,
    /// so it can be far closer to the popup edge without moving the
    /// Search icon/text at all.
    package static let surfaceHorizontalInset: CGFloat = 9
    /// Purely optical top-gap correction — see the `.offset` call site.
    /// Applied to the background layer only, never to content.
    package static let surfaceVerticalOffset = PanelFieldSurface.verticalOffset
    /// Readable fallback fill for solid themes; a material theme can render
    /// the same boundary through its transient surface treatment rather than the
    /// switcher's own translucent `controlSurface` — at the omnibox's much
    /// larger size, that translucency let calendar content underneath
    /// show/blend through instead of reading as one solid surface.
    private var surfaceFill: Color { theme.searchSurface }

    private var isExpanded: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The palette's elevated surface: expanded, unless the Search view is
    /// showing the results (then the field sits flat in the toolbar row).
    private var showsSurface: Bool { isExpanded && !palette.isResultsViewShown }

    package var body: some View {
        // One VStack, one background, one shape — header and suggestion
        // are the same foreground layer, not two overlapping surfaces
        // that could show a gap/seam or let content bleed through at
        // their boundary.
        VStack(spacing: 0) {
            headerRow
            if showsSurface, !palette.actions.isEmpty {
                resultsList
                    .padding(.horizontal, Self.suggestionRowHorizontalInset)
                    .padding(.top, Self.suggestionRowTopGap)
                    .padding(.bottom, Self.suggestionRowBottomInset)
                keyHintFooter
            }
        }
        .background(
            PaletteKeyMonitor(
                isEnabled: isExpanded,
                isRefining: palette.isRefining,
                onMove: { palette.moveSelection($0) },
                onRefine: { palette.refine() },
                onTab: { backward in
                    if let event = palette.eventEdit {
                        quickAddFocus = QuickAddField.next(after: quickAddFocus, in: QuickAddField.eventOrder(isAllDay: event.isAllDay),
                                                           backward: backward)
                    } else {
                        quickAddFocus = QuickAddField.next(after: quickAddFocus, hasDate: palette.edit?.day != nil, backward: backward)
                    }
                },
                onCreate: { palette.createFromKeyboard() }
            )
        )
        // Explicit — this container must claim the *full* width offered to
        // it (the parent/full-width layer the background then insets
        // from), not just whatever width its content happens to need.
        // Without this, the background risks tracking the header content's
        // own narrower footprint instead of the popup's full inner width,
        // which is what produced a background inset that tracked (and
        // inherited) the header's own ~18pt content padding instead of the
        // independent, much smaller gap intended here.
        .frame(maxWidth: .infinity)
        .background(
            // Offset on the background layer only — the Search input/
            // header content above (and the result row's own text/icon)
            // keep their exact existing coordinates. This is purely
            // optical: the menu-bar pointer shape makes the gap between
            // the popup's top edge and the surface read as tighter than
            // the equivalent left/right gaps, even though the numeric
            // inset is the same; nudging just the visible surface down a
            // few points corrects that without moving anything the user
            // actually reads as content.
            ThemedSurface(role: .transient, fill: showsSurface ? surfaceFill : .clear,
                            shape: RoundedRectangle(cornerRadius: Self.surfaceCornerRadius, style: .continuous))
                // Collapsed it's invisible: let presses reach the drag band.
                .allowsHitTesting(showsSurface)
                .padding(.horizontal, Self.surfaceHorizontalInset)
                .offset(y: Self.surfaceVerticalOffset)
                // A restrained single shadow, only while expanded — just
                // enough to separate the surface from the calendar behind
                // it, not the stronger shadow the hint/detail popovers use
                // (that would read as a floating card, not an omnibox).
                // No spread, no second ambient layer.
                .surfaceElevation(.transient, fallback: .init(
                    color: showsSurface ? theme.chrome.searchShadow : .clear, radius: 11, y: 3))
                .opacity(theme.surfaces == nil || showsSurface ? 1 : 0)
        )
        // Explicit, generous z-index — this surface must never be drawn
        // under the calendar/agenda content beneath it, regardless of
        // ordering changes elsewhere in the view tree.
        .zIndex(100)
        .animation(.easeOut(duration: isExpanded ? 0.16 : 0.13), value: isExpanded)
        .onAppear {
            searchFocus.wrappedValue = true
            palette.update(query: query)
        }
        .onChange(of: query) { _, newValue in palette.update(query: newValue) }
        // Expanding moves focus into Quick Add; collapsing brings it back.
        // Tab from the list: Quick Add opens with the whole title selected,
        // ready to be typed over. Collapsing hands focus back to the query.
        .onChange(of: palette.isRefining) { _, refining in
            if refining {
                quickAddFocus = .title
                DispatchQueue.main.async { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
            } else {
                quickAddFocus = nil
                searchFocus.wrappedValue = true
            }
        }
        .onDisappear { palette.clear() }
    }

    /// The Search view: the query stays in the toolbar row as Ask's
    /// composer's twin — the field surface, border to border, under the
    /// folded view switcher.
    private var showsField: Bool { palette.isResultsViewShown }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.secondaryText)

            TextField("", text: $query, prompt: Text(L10n.tr("searchbarview.search", "Search")).foregroundStyle(theme.secondaryText))
                .textFieldStyle(.plain)
                .font(AppTheme.TextStyle.eventTitle)
                .foregroundStyle(theme.primaryText)
                .focused(searchFocus)
                .onSubmit { palette.submitQuery() }
                // Collapsed and empty, the field is as wide as "Search": the
                // rest of the row is the panel's drag area (it's focused on
                // open anyway, so typing just works).
                .fixedSize(horizontal: !isExpanded && query.isEmpty, vertical: false)

            Spacer(minLength: 0)
        }
        // The view switcher is the panel toolbar's (drawn once, above this
        // layer); the field leaves its room unless the palette is open.
        .padding(.trailing, showsSurface || showsField ? 0 : PanelToolbarMetrics.trailingReserve)
        .padding(.horizontal, AppTheme.horizontalPadding)
        .frame(height: Self.headerHeight)
        .background {
            PanelFieldSurface()
                .padding(.horizontal, Self.surfaceHorizontalInset)
                .opacity(showsField ? 1 : 0)
        }
    }

    package init(
        query: Binding<String>,
        searchFocus: FocusState<Bool>.Binding,
        palette: SearchPaletteModel,
        taskCoordinator: CalendarTaskCoordinator? = nil
    ) {
        self._query = query
        self.searchFocus = searchFocus
        self.palette = palette
        self.taskCoordinator = taskCoordinator
    }
}

extension EventConflict {
    func color(theme: ThemePalette) -> Color {
        switch self {
        case .busy: theme.conflict.busy
        case .unconfirmed: theme.conflict.unconfirmed
        case .free: theme.conflict.free
        }
    }

    var spokenDescription: String {
        switch self {
        case .busy: L10n.tr("searchbarview.overlaps.an.accepted.event", "Overlaps an accepted event")
        case .unconfirmed: L10n.tr("searchbarview.overlaps.an.event.not.yet.accepted", "Overlaps an event not yet accepted")
        case .free: L10n.tr("searchbarview.time.is.free", "Time is free")
        }
    }
}
