import SwiftUI
import Domain

/// The Action Panel (⌘K): the selection's right-click menu — same items,
/// submenus and checkmarks — first, then what can always be done here.
/// Searchable by title.
///
/// Keys (the field keeps focus): ↑ ↓ choose, ↩ runs or opens a submenu,
/// → opens one, ← leaves it, Esc leaves it, then closes (as does ⌘K). Rows
/// come from `PanelActionList`; running one is the caller's.
package struct ActionsListView: View {
    @Environment(\.themePalette) private var theme

    /// The entries for a query.
    package let entries: (String) -> [ActionEntry]
    package let onRun: (ActionRow) -> Void
    package let onClose: () -> Void

    @State private var query = ""
    @State private var selectedID: String?
    /// The submenu shown in place of the list (one level, as in the menu).
    @State private var submenu: ActionSubmenu?
    @FocusState private var isFieldFocused: Bool

    private static let rowHeight: CGFloat = 30
    private static let maxVisibleRows: CGFloat = 10

    /// What's listed at the current level, separators included.
    private var shown: [ActionEntry] {
        if let submenu { return PanelActionList.items(of: submenu, matching: query).map(ActionEntry.item) }
        return entries(query)
    }

    package var body: some View {
        let shown = shown
        let selectable = Self.selectable(in: shown)
        let selected = selected(in: selectable)
        VStack(alignment: .leading, spacing: 0) {
            field
            WorkspaceRule(.section)
            if let submenu { backRow(submenu) }
            if selectable.isEmpty {
                Text(L10n.tr("actionslistview.no.actions", "No matching actions"))
                    .font(AppTheme.TextStyle.eventSubtitle)
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: Self.rowHeight * 2)
            } else {
                list(shown, selected: selected)
            }
        }
        .onAppear { isFieldFocused = true }
        // Typing starts from the first match; clearing (into or out of a
        // submenu) keeps the row chosen there.
        .onChange(of: query) { _, new in if !new.isEmpty { selectedID = nil } }
    }

    private var field: some View {
        TextField("", text: $query, prompt: Text(L10n.tr("actionslistview.search.actions", "Search actions"))
            .foregroundStyle(theme.secondaryText))
            .textFieldStyle(.plain)
            .themedTextInput()
            .font(AppTheme.TextStyle.eventTitle)
            .foregroundStyle(theme.primaryText)
            .focused($isFieldFocused)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .onSubmit { if let selected = selected(in: Self.selectable(in: shown)) { activate(selected) } }
            .onKeyPress(.downArrow) { move(1); return .handled }
            .onKeyPress(.upArrow) { move(-1); return .handled }
            .onKeyPress(.rightArrow) { openSelectedSubmenu() ? .handled : .ignored }
            .onKeyPress(.leftArrow) { leaveSubmenuByKey() ? .handled : .ignored }
            .onKeyPress(.escape) {
                if submenu != nil { leaveSubmenu() } else { onClose() }
                return .handled
            }
            .onKeyPress("k", phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                onClose()
                return .handled
            }
    }

    private static func selectable(in shown: [ActionEntry]) -> [ActionEntry] {
        shown.filter { if case .separator = $0 { false } else { true } }
    }

    private func selected(in selectable: [ActionEntry]) -> ActionEntry? {
        selectable.first { $0.id == selectedID } ?? selectable.first
    }

    private func list(_ shown: [ActionEntry], selected: ActionEntry?) -> some View {
        ScrollViewReader { proxy in
            // The app's own slim scroller, as in every other list.
            ThemedScrollView {
                VStack(spacing: 2) {
                    ForEach(shown) { entry in
                        switch entry {
                        case .separator:
                            WorkspaceRule(.section).padding(.vertical, 4).padding(.horizontal, 8)
                        case .item, .submenu:
                            row(entry, isSelected: entry.id == selected?.id).id(entry.id)
                        }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: Self.rowHeight * Self.maxVisibleRows + 12)
            .onChange(of: selectedID) { _, id in if let id { proxy.scrollTo(id) } }
        }
    }

    private func row(_ entry: ActionEntry, isSelected: Bool) -> some View {
        let item: ActionItem? = if case .item(let item) = entry { item } else { nil }
        let menu: ActionSubmenu? = if case .submenu(let menu) = entry { menu } else { nil }
        let title = item?.title ?? menu?.title ?? ""
        let symbol = item?.symbol ?? menu?.symbol
        let tint = item?.isDestructive == true ? theme.workspace.destructive : theme.primaryText
        return Button { activate(entry) } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol ?? "circle")
                    .foregroundStyle(item?.isDestructive == true ? tint : theme.secondaryText)
                    .frame(width: 18)
                    .opacity(symbol == nil ? 0 : 1)
                Text(title)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if item?.isChecked == true {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.primaryText)
                } else if menu != nil {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.secondaryText)
                } else if let label = item?.shortcut.flatMap({ KeyboardShortcutSettings.shared.shortcut(for: $0)?.displayLabel }) {
                    KeyboardShortcutKey(label)
                }
            }
            .font(AppTheme.TextStyle.eventSubtitle)
            .padding(.horizontal, 8)
            .frame(height: Self.rowHeight)
            .contentShape(Rectangle())
            .background { if isSelected { WorkspaceSelectionSurface() } }
        }
        .buttonStyle(.plain)
        // Rows answer clicks only: a focused row took Return (and Space) for
        // itself — the first one, Mark as Completed, whatever was chosen.
        .focusable(false)
        .onHover { if $0 { selectedID = entry.id } }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(item?.isChecked == true ? L10n.tr("actionslistview.checked", "Checked") : "")
    }

    /// The submenu's title, a way back up.
    private func backRow(_ menu: ActionSubmenu) -> some View {
        Button(action: leaveSubmenu) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                Text(menu.title)
            }
            .font(AppTheme.TextStyle.eventSubtitle)
            .foregroundStyle(theme.secondaryText)
            .padding(.horizontal, 14)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func activate(_ entry: ActionEntry) {
        switch entry {
        case .item(let item): onRun(item.row)
        case .submenu(let menu): open(menu)
        case .separator: break
        }
    }

    /// → opens the selected submenu; otherwise the caret's (false).
    private func openSelectedSubmenu() -> Bool {
        guard case .submenu(let menu)? = selected(in: Self.selectable(in: shown)) else { return false }
        open(menu)
        return true
    }

    /// ← leaves the submenu open; otherwise the caret's (false).
    private func leaveSubmenuByKey() -> Bool {
        guard submenu != nil, query.isEmpty else { return false }
        leaveSubmenu()
        return true
    }

    /// Into a submenu, on its current value (else its first choice).
    private func open(_ menu: ActionSubmenu) {
        submenu = menu
        query = ""
        selectedID = (menu.items.first(where: \.isChecked) ?? menu.items.first).map { ActionEntry.item($0).id }
    }

    /// Back to the list, on the submenu it came from.
    private func leaveSubmenu() {
        let left = submenu.map { ActionEntry.submenu($0).id }
        submenu = nil
        query = ""
        selectedID = left
    }

    private func move(_ delta: Int) {
        let selectable = Self.selectable(in: shown)
        guard !selectable.isEmpty else { return }
        let current = selected(in: selectable).flatMap { entry in selectable.firstIndex { $0.id == entry.id } } ?? 0
        selectedID = selectable[min(max(current + delta, 0), selectable.count - 1)].id
    }

    package init(entries: @escaping (String) -> [ActionEntry], onRun: @escaping (ActionRow) -> Void,
                 onClose: @escaping () -> Void) {
        self.entries = entries
        self.onRun = onRun
        self.onClose = onClose
    }
}
