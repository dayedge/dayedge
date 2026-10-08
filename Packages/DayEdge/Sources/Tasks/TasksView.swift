import SwiftUI
import Domain
import UI

/// Header top edges, keyed by section id, for the scrollspy.
private struct SectionOffsetKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// The Tasks column: one continuous document — Needs attention, then a
/// section per list. The navigator on top jumps between those landmarks
/// (like month navigation in Calendar); ← / → do the same from the
/// keyboard, ↑ / ↓ move between tasks. Permanently mounted like Month and
/// Day; keyboard handling is only live while `isActive`.
package struct TasksView: View {
    @Environment(\.themePalette) private var theme
    @Environment(\.timeFormat) private var timeFormat

    package let store: TaskStore
    /// The shared search field's text, used here as a live filter.
    package let query: String
    package let isActive: Bool
    package let navigationRequest: VerticalNavigationRequest?

    private static let scrollSpace = "tasksScroll"
    /// Below the top of the pinned area where a section counts as reached.
    private static let activationSlack: CGFloat = 28

    /// True only while the user's own scroll gesture is driving the view, so
    /// programmatic jumps never fight the scrollspy.
    @State private var isUserScrolling = false
    /// The scroll bar's knob is dragged (SwiftUI reports no phase for it).
    @State private var isScrollerTracking = false
    @State private var barHeight: CGFloat = 0

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    package var body: some View {
        Group {
            // The permission state replaces the whole view, title included.
            if store.needsAccess {
                PermissionStateView(subject: .reminders, status: store.accessStatus) {
                    Task { await store.performAccessAction() }
                }
            } else {
                list
            }
        }
        .onChange(of: navigationRequest) { _, request in
            guard isActive, let request else { return }
            store.moveSelection(request.direction, query: query)
        }
        .task { await store.load() }
        .task(id: isActive) {
            if isActive { await store.activate() }
        }
    }

    private var list: some View {
        let sections = store.sections(query: query)
        return ScrollViewReader { proxy in
            ThemedScrollView(appliesBottomEdgeEffect: true,
                             onScrollerTracking: { isScrollerTracking = $0 }, content: {
                if sections.isEmpty {
                    emptyState
                } else {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(sections) { section in
                            Section {
                                rows(for: section)
                            } header: {
                                header(for: section)
                            }
                            .id(Self.sectionAnchor(section.id))
                        }
                    }
                    .padding(.bottom, 12)
                }
            })
            .coordinateSpace(.named(Self.scrollSpace))
            .onScrollPhaseChange { _, phase in
                isUserScrolling = phase == .interacting || phase == .decelerating
            }
            .onPreferenceChange(SectionOffsetKey.self) { offsets in
                updateSpy(offsets)
            }
            .floatingTopBar { topBar }
            .onChange(of: store.jumpRequest) { _, request in
                guard let request else { return }
                withAnimation(.smooth(duration: 0.35)) {
                    proxy.scrollTo(Self.sectionAnchor(request.sectionID), anchor: .top)
                }
            }
            .onChange(of: store.scrollRequest) { _, request in
                guard let request else { return }
                withAnimation(.smooth(duration: 0.35)) {
                    proxy.scrollTo(request.taskID, anchor: .center)
                }
            }
        }
    }

    private static func sectionAnchor(_ id: String) -> String { "section-\(id)" }

    // MARK: Scrollspy

    private func updateSpy(_ offsets: [String: CGFloat]) {
        guard isUserScrolling || isScrollerTracking, isActive, !isSearching else { return }
        let order = store.navigableSections(query: query).map(\.id)
        let line = (FloatingBar.overlapsContent ? barHeight : 0) + Self.activationSlack
        store.setActiveSectionFromScroll(TaskSectionSpy.activeSection(
            headerOffsets: offsets, order: order,
            current: store.currentSectionID(query: query), activationLine: line
        ))
    }

    // MARK: Top bar (title + navigator)

    private var topBar: some View {
        let subtitle = store.headerSubtitle(query: query)
        return VStack(alignment: .leading, spacing: 0) {
            LargeTitleHeader {
                Text(L10n.tr("tasksview.tasks", "Tasks"))
            } subtitle: {
                if let subtitle {
                    PeriodHeaderSubtitle(text: subtitle)
                }
            }

            if !isSearching {
                let items = navigatorItems
                if !items.isEmpty {
                    // Location (scrolling chips) and arrangement (a fixed
                    // sort control) stay separate: the button never
                    // scrolls away with the chips.
                    HStack(spacing: 0) {
                        TaskNavigatorView(
                            items: items,
                            activeID: store.currentSectionID(query: query),
                            trailingInset: 12,
                            onSelect: { store.jump(to: $0) }
                        )
                        Rectangle()
                            .fill(theme.secondaryControl.divider)
                            .frame(width: 1, height: 16)
                        TaskSortButton(store: store)
                            .padding(.leading, 10)
                            .padding(.trailing, AppTheme.horizontalPadding - 4)
                    }
                    .padding(.top, 8)
                }
            }
            Color.clear.frame(height: AppTheme.PeriodHeader.subtitleToContent - 2)
        }
        // Match the shell's material while shielding the title from scrolled rows.
        // Keep the existing overlap that closes fractional-pixel header gaps.
        .background(
            ThemedSurface(role: .window, fill: theme.background, shape: Rectangle())
                .padding(.bottom, -6).allowsHitTesting(false)
        )
        .background(
            GeometryReader { geo in
                Color.clear.onChange(of: geo.size.height, initial: true) { _, height in barHeight = height }
            }
        )
    }

    private var navigatorItems: [TaskNavigatorItem] {
        TaskNavigatorItem.items(from: store.sections(query: ""))
    }

    private var emptyState: some View {
        Text(isSearching ? L10n.tr("tasksview.no.matching.reminders", "No matching reminders") : L10n.tr("tasksview.no.reminders", "No reminders"))
            .font(AppTheme.TextStyle.eventSubtitle)
            .foregroundStyle(theme.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(.top, 80)
    }

    // MARK: Sections

    @ViewBuilder
    private func header(for section: TaskSection) -> some View {
        Group {
            if section.kind == .completed {
                TaskSectionHeaderView(
                    section: section,
                    onToggleCollapse: { withAnimation(.smooth(duration: 0.25)) { store.toggleCompletedExpanded() } },
                    isCollapsed: section.tasks.isEmpty
                )
            } else if section.isNavigable {
                TaskSectionHeaderView(section: section, onOpen: { store.jump(to: section.id) })
            } else {
                TaskSectionHeaderView(section: section)
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: SectionOffsetKey.self,
                    value: section.isNavigable
                        ? [section.id: geo.frame(in: .named(Self.scrollSpace)).minY] : [:]
                )
            }
        )
    }

    @ViewBuilder
    private func rows(for section: TaskSection) -> some View {
        ForEach(section.tasks) { task in
            row(task, in: section)
        }
        if section.canExpand {
            showMoreRow(section)
        }
        // Completed comes in batches: more rows only when asked.
        if section.kind == .completed, !section.tasks.isEmpty, section.hiddenCount > 0 {
            quietRow(L10n.tr("tasksview.show.more", "Show more")) { store.showMoreCompleted() }
        }
    }

    private func row(_ task: TaskItem, in section: TaskSection) -> some View {
        let list = store.list(for: task)
        let tint = list?.color ?? theme.secondaryText
        // A list's own section already names the list.
        let showsList = section.kind == .needsAttention || section.kind == .completed || section.kind == .results
        // Completed rows say when they were finished, not when they were due.
        let due = section.kind == .completed
            ? store.completionText(for: task).map { TaskDueText(text: $0, isOverdue: false) }
            : store.dueText(for: task, format: timeFormat)

        return TaskRowView(
            task: task,
            listName: showsList ? list?.title : nil,
            tint: tint,
            due: due,
            isSelected: store.selectedTaskID == task.id,
            isDetailPresented: store.presentedDetailID == task.id,
            isReadOnly: store.isReadOnly(task),
            isArriving: store.arrivingTaskID == task.id,
            onToggle: { store.toggleCompleted(task.id) },
            onTap: {
                store.select(task.id)
                store.toggleDetail(for: task.id)
            }
        )
        .id(task.id)
        .popover(
            isPresented: Binding(
                get: { store.presentedDetailID == task.id },
                set: { store.setDetailPresented($0, for: task.id) }
            ),
            arrowEdge: .leading
        ) {
            TaskDetailPopoverView(
                task: task,
                lists: store.lists,
                onEdit: { store.edit($0, taskID: task.id) },
                onToggleCompleted: { store.toggleCompleted(task.id, closingDetail: true) },
                isReadOnly: store.isReadOnly(task)
            )
        }
        .contextMenu { contextMenu(for: task) }
    }

    /// Expands/collapses this one section in place; ← / → still jump out
    /// of it instantly, however long it gets.
    private func showMoreRow(_ section: TaskSection) -> some View {
        quietRow(
            section.isExpanded ? L10n.tr("tasksview.show.less", "Show less") : L10n.tr("tasksview.show.more.45f9a2", "Show \(String(describing: section.hiddenCount)) more"),
            symbol: section.isExpanded ? "chevron.up" : "chevron.down"
        ) {
            withAnimation(.smooth(duration: 0.25)) { store.toggleExpanded(section.id) }
        }
    }

    private func quietRow(_ title: String, symbol: String = "chevron.down", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
            }
            .font(AppTheme.TextStyle.eventSubtitle)
            .foregroundStyle(theme.secondaryText)
            .padding(.horizontal, AppTheme.horizontalPadding)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Context menu

    private func contextMenu(for task: TaskItem) -> some View {
        TaskContextMenuItems(task: task, isReadOnly: store.isReadOnly(task)) { store.perform($0, on: task) }
    }

    package init(store: TaskStore, query: String, isActive: Bool, navigationRequest: VerticalNavigationRequest?) {
        self.store = store
        self.query = query
        self.isActive = isActive
        self.navigationRequest = navigationRequest
    }
}
