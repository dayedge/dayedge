import SwiftUI
import Domain
import UI

extension SearchBarView {
    /// Icon | title over interpretation. No keys here — see the footer.
    func actionRow(_ action: PaletteAction, subtitle: String? = nil, onTap: (() -> Void)? = nil) -> some View {
        let metadata = subtitle ?? action.subtitle
        return paletteRow(isSelected: palette.selectedKind == action.kind, title: action.title, metadata: metadata) {
            icon(for: action.kind)
                .overlay(alignment: .topTrailing) { conflictDot(action.conflict) }
        }
        .onTapGesture {
            palette.select(action.kind)
            if let onTap { onTap() } else { palette.executeSelected() }
        }
        .accessibilityLabel(action.accessibilityLabel ?? action.title)
        .accessibilityValue(metadata ?? "")
    }

    /// A row of the palette's list: the leading mark in the icon column, the title, and the metadata at the trailing
    /// edge, one line high. A long title runs on and fades out where the metadata begins — never wraps, never "…".
    /// The caller adds what a click does and what VoiceOver says.
    func paletteRow(isSelected: Bool, title: String, metadata: String?, @ViewBuilder leading: () -> some View) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.suggestionRowCornerRadius, style: .continuous)
        return HStack(alignment: .firstTextBaseline, spacing: Self.iconToText) {
            leading()
                .frame(width: Self.iconColumn, height: 16)
                .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 4 }

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.primaryText)
                .fadingOverflow()

            if let metadata {
                Text(metadata)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, Self.rowInsetH)
        .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
        .background(shape.fill(isSelected ? theme.chrome.rowHover : Color.clear))
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// On Create event's icon: is that time free? Red — an accepted event
    /// is there; yellow — one not accepted yet; green — free.
    @ViewBuilder
    private func conflictDot(_ conflict: EventConflict?) -> some View {
        if let conflict {
            Circle()
                .fill(conflict.color(theme: theme))
                .frame(width: AppTheme.Conflict.dotSize, height: AppTheme.Conflict.dotSize)
                .overlay(Circle().stroke(theme.searchSurface, lineWidth: 1.5))
                .offset(x: 3, y: -2)
                .accessibilityLabel(conflict.spokenDescription)
        }
    }

    /// An action that can't run right now (Search with no matches): on the
    /// same axis as real actions but clearly inactive — one line, its note
    /// at a shared right edge, no selection, no keys, no tap action.
    func placeholderRow(_ action: PaletteAction, subtitle overridden: String? = nil) -> some View {
        let subtitle = overridden ?? action.subtitle
        return HStack(spacing: Self.iconToText) {
            icon(for: action.kind)
                .frame(width: Self.iconColumn)
            Text(action.title)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.primaryText.opacity(0.6))
            Spacer(minLength: 8)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.primaryText.opacity(0.38))
            }
        }
        .padding(.horizontal, Self.rowInsetH)
        .frame(height: Self.placeholderRowHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subtitle.map { "\(action.title), \($0)" } ?? action.title)
    }

    /// The meeting a new event runs into: a top-3 result row without its
    /// date (the event being made says the day) or Join pill; informational.
    @ViewBuilder
    func overlapRow(_ event: AgendaEventModel) -> some View {
        if let taskCoordinator, let start = event.startDate {
            let calendar = Calendar.autoupdatingCurrent
            let day = calendar.startOfDay(for: start)
            SearchResultRow(
                item: SearchResultRowItem(result: .event(event), day: day, isToday: calendar.isDateInToday(day),
                                          isOutsideCurrentYear: !calendar.isDate(day, equalTo: Date(), toGranularity: .year)),
                taskCoordinator: taskCoordinator,
                showsJoin: false,
                showsDateColumn: false
            )
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    func icon(for kind: PaletteAction.Kind) -> some View {
        switch kind {
        case .goToDate:
            Image(systemName: "calendar")
                .font(.system(size: 13))
                .foregroundStyle(theme.chrome.mutedText)
        case .createTask:
            // A task looks like a task everywhere — the hollow ring — but
            // here it only says "this creates a task": smaller, neutral,
            // no hover.
            TaskCheckbox(color: theme.chrome.mutedText, isCompleted: false, size: 13)
                .allowsHitTesting(false)
        case .createEvent:
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 13))
                .foregroundStyle(theme.chrome.mutedText)
        case .search:
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(theme.chrome.placeholderText)
        case .askAI:
            Image(systemName: "sparkle")
                .font(.system(size: 12))
                .foregroundStyle(theme.chrome.mutedText)
        }
    }

    /// What the keys do now, for the selected action — one shared footer
    /// of small keycaps, bottom-right, set apart by whitespace. It
    /// crossfades (with a tiny lift) as the selection or state changes.
    var keyHintFooter: some View {
        let hints = palette.keyHints
        return HStack(spacing: Self.footerHintSpacing) {
            Spacer(minLength: 0)
            ForEach(hints) { hint in
                KeyboardShortcutHint(key: hint.glyph, action: hint.label, accessibilityLabel: hint.accessibilityLabel)
            }
        }
        .frame(height: AppTheme.Keycap.compactHeight)
        .padding(.top, Self.footerInsetTop)
        // On the card's trailing edge.
        .padding(.trailing, Self.suggestionRowHorizontalInset)
        .padding(.bottom, Self.footerInsetBottom)
        .id(hints.map(\.id).joined())
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 2)))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hints)
    }
}
