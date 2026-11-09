import SwiftUI
import Domain
import UI

/// The Command Window's Tasks sidebar: Overview, the Reminders lists,
/// Completed. Today, Next 7 Days and All Tasks are filters — the current
/// one is selected. Needs Attention, the lists and Completed are the
/// filtered list's sections, as the popover's chips are: a click jumps, the
/// one in view is marked as scrolling and ← / → move, and one the filter
/// leaves empty is dimmed. A row never changes a task.
package struct TaskSidebarView: View {
    @Environment(\.themePalette) private var theme

    package let store: TaskStore

    private static let rowSpacing: CGFloat = 2
    /// About five lists in view (the half row says there's more); the rest
    /// scroll in place, between Overview and Completed.
    private static let visibleLists: CGFloat = 5.5

    package var body: some View {
        let counts = store.filterCounts
        let current = TaskSidebarPlace(store: store)
        let lists = store.shownLists
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            caption(L10n.tr("tasksidebar.overview", "Overview"))
            ForEach(store.smartViews, id: \.self) { view in
                let shortcut = KeyboardShortcutSettings.shared.shortcut(for: .taskView(view))?.displayLabel
                let symbol = Image(systemName: view.symbolName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                if let filter = view.filter {
                    TaskSidebarRow(title: view.title, count: counts[filter] ?? 0, shortcut: shortcut,
                                   isSelected: current.isSelected(filter), marker: symbol) { store.select(filter) }
                } else {
                    sectionRow(.needsAttention, title: view.title, current: current, shortcut: shortcut) { symbol }
                }
            }

            if !lists.isEmpty {
                caption(L10n.tr("tasksidebar.my.lists", "My Lists"), count: counts[store.filter])
                    .padding(.top, 10)
                listRows(lists, current: current)
            }

            if store.isSmartVisible(.completed) {
                sectionRow(.completed, title: TaskSmartSection.completed.title, current: current) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(theme.secondaryText)
                }
                .padding(.top, 10)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.top, LargeTitleHeader<EmptyView, EmptyView, EmptyView>.topPadding)
        .padding(.bottom, 12)
    }

    package init(store: TaskStore) {
        self.store = store
    }

    private func listRows(_ lists: [CalendarSource], current: TaskSidebarPlace) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: Self.rowSpacing) {
                    ForEach(lists) { list in
                        let kind = TaskSection.Kind.list(list.id)
                        sectionRow(kind, title: list.title, current: current) {
                            Circle().fill(list.color).frame(width: 7, height: 7)
                        }
                        .id(kind.id)
                    }
                }
            }
            .scrollIndicators(.automatic)
            .frame(height: min(CGFloat(lists.count), Self.visibleLists) * (sidebarRowHeight + Self.rowSpacing))
            // Keeps the list in view in the lists' viewport (other ids: no-op).
            .onChange(of: current.sectionInView) { _, id in
                guard let id else { return }
                withAnimation(.smooth(duration: 0.25)) { proxy.scrollTo(id) }
            }
        }
    }

    private func caption(_ title: String, count: Int? = nil) -> some View {
        HStack {
            Text(title.uppercased())
            Spacer(minLength: 8)
            if let count { Text("\(count)").monospacedDigit() }
        }
        .font(AppTheme.TextStyle.weekdayLabel)
        .foregroundStyle(theme.secondaryText)
        .padding(.horizontal, AppTheme.horizontalPadding - 8)
        .padding(.bottom, 2)
    }

    private func sectionRow<Marker: View>(_ kind: TaskSection.Kind, title: String, current: TaskSidebarPlace,
                                          shortcut: String? = nil, @ViewBuilder marker: () -> Marker) -> some View {
        let id = kind.id
        return TaskSidebarRow(title: title, count: current.count(id), shortcut: shortcut, isInView: current.isInView(id),
                              isEnabled: current.contains(id), marker: marker()) { store.jump(to: id) }
    }
}

/// Where the document is: its filter, its sections and their counts, and
/// the section in view.
struct TaskSidebarPlace: Equatable {
    let filter: TaskFilter
    let sectionInView: String?
    /// Section id → its count, for the sections the filter leaves.
    let counts: [String: Int]

    init(filter: TaskFilter, sectionInView: String?, counts: [String: Int]) {
        self.filter = filter
        self.sectionInView = sectionInView
        self.counts = counts
    }

    @MainActor init(store: TaskStore) {
        let sections = store.navigableSections()
        self.init(filter: store.filter, sectionInView: store.currentSectionID(),
                  counts: Dictionary(sections.map { ($0.id, $0.totalCount) }, uniquingKeysWith: { first, _ in first }))
    }

    func isSelected(_ row: TaskFilter) -> Bool { row == filter }

    func isInView(_ section: String) -> Bool { section == sectionInView }

    /// Under this filter the section has tasks, so its row can jump.
    func contains(_ section: String) -> Bool { counts[section] != nil }

    func count(_ section: String) -> Int { counts[section] ?? 0 }
}

private let sidebarRowHeight: CGFloat = 30

/// One row; its own hover, so moving over the rows redraws only them.
private struct TaskSidebarRow<Marker: View>: View {
    @Environment(\.themePalette) private var theme

    let title: String
    let count: Int
    var shortcut: String?
    /// The filter on screen.
    var isSelected = false
    /// The section in view.
    var isInView = false
    /// False for a section the filter leaves empty: dimmed, inert.
    var isEnabled = true
    let marker: Marker
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                marker
                    .frame(width: 14)
                Text(verbatim: title)
                    .font(AppTheme.TextStyle.eventTitle)
                    .fontWeight(isSelected || isInView ? .semibold : .regular)
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(count)")
                    .font(AppTheme.TextStyle.eventSubtitle.monospacedDigit())
                    .foregroundStyle(theme.secondaryText)
                if let shortcut {
                    KeyboardShortcutKey(shortcut)
                }
            }
            .padding(.horizontal, AppTheme.horizontalPadding - 8)
            .frame(height: sidebarRowHeight)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.45)
            .background {
                if isSelected {
                    WorkspaceSelectionSurface()
                } else if isInView || (isHovered && isEnabled) {
                    ThemedSurface(role: .hover, fill: theme.chrome.rowHover,
                                  shape: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(L10n.tr("tasksidebar.count", "\(count) tasks")))
        .accessibilityAddTraits(isSelected || isInView ? .isSelected : [])
    }
}
