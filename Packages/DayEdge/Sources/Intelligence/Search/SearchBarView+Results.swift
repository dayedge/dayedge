import SwiftUI
import Domain
import UI

extension SearchBarView {
    /// Rows say what the app understood; the footer says what the keys do.
    /// Real actions first — the selected one on the one rounded surface —
    /// then the placeholders, quieter, on the same axis. Create Task grows
    /// into Quick Add in the same place.
    var resultsList: some View {
        VStack(spacing: Self.rowSpacing) {
            ForEach(palette.visibleActions) { action in
                if action.kind == .createTask, palette.isRefining, let edit = palette.edit {
                    quickAddEditor(edit)
                        .transition(.opacity)
                } else if action.kind == .createEvent, palette.isRefining, let edit = palette.eventEdit {
                    eventEditor(edit)
                        .transition(.opacity)
                } else if action.kind == .search {
                    if palette.isSearchSelectable {
                        actionRow(action, subtitle: searchSummary, onTap: { palette.openResultsView() })
                        searchPreview
                    } else {
                        placeholderRow(action, subtitle: searchSummary)
                    }
                } else if action.isEnabled {
                    actionRow(action)
                } else {
                    placeholderRow(action)
                }
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: palette.selection)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: palette.isRefining)
    }

    /// "24 results · March 2026", live as they arrive.
    private var searchSummary: String { palette.results.summary }

    /// Up to three results under the Search row — informational, not
    /// keyboard stops: the date tile says when, the agenda row says what.
    @ViewBuilder
    private var searchPreview: some View {
        let preview = palette.results.preview
        if let taskCoordinator, !preview.isEmpty {
            VStack(spacing: 0) {
                ForEach(preview) { item in
                    SearchResultRow(
                        item: item,
                        taskCoordinator: taskCoordinator,
                        isSelected: palette.selection == .result(item.id),
                        isDetailPresented: palette.presentedEventID != nil && item.id == "event:\(palette.presentedEventID!)",
                        showsJoin: false,
                        detailPresentationRequest: palette.eventDetailRequest,
                        onDetailPresentationChange: { isShowing in
                            if case .event(let event) = item.result {
                                palette.eventDetailPresentationChanged(eventID: event.id, isShowing: isShowing)
                            }
                        },
                        onTap: { palette.selectResult(item.id) },
                        onDoubleTap: {
                            palette.selectResult(item.id)
                            palette.refine()
                        }
                    )
                    // Its menus offer Tab's "Show in Calendar / Tasks" too.
                    .environment(\.searchResultReveal) { palette.onShowResult(item) }
                }
            }
            // Children of Search: indented, so the selection starts there too.
            .padding(.leading, AppTheme.Search.nestedLeadingInset)
            // Close under Search, with a hairline of space so the two
            // selection surfaces never touch; Ask follows at the list's own
            // row spacing — one group, not a separate section.
            .padding(.top, AppTheme.Search.previewTopGap)
            .transition(.opacity)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: preview.map(\.id))
        }
    }
}
