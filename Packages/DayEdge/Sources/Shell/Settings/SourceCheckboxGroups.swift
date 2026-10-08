import SwiftUI
import Domain
import UI

/// Settings' "which sources does the app use" list: checkboxes grouped by
/// account. Shared by the Calendars and Tasks panes.
struct SourceCheckboxGroups: View {
    @Environment(\.themePalette) private var theme

    let store: SourceVisibilityStore
    let kind: SelectionKind
    let title: String
    let footer: String

    var body: some View {
        let groups = SelectionGroups.bySource(store.allItems, kind: kind) { store.isEnabled($0) }
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                SettingsGroup(
                    header: index == 0 ? title : nil,
                    footer: index == groups.count - 1 ? footer : nil
                ) {
                    Text(group.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.settings.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                        .padding(.horizontal, 12)
                    ForEach(group.items) { item in row(item) }
                }
            }
        }
    }

    /// Only Reminders lists say so; calendars' own read-only state is not
    /// surfaced here.
    private func isReadOnly(_ item: SelectionItem) -> Bool {
        guard kind == .reminderList else { return false }
        return store.allItems.first { $0.id == item.id }.map { !$0.allowsModifications } ?? false
    }

    private func row(_ item: SelectionItem) -> some View {
        let isOn = Binding(get: { store.isEnabled(item.id) }, set: { store.setEnabled($0, id: item.id) })
        return HStack(spacing: 8) {
            Toggle(isOn: isOn) {
                HStack(spacing: 8) {
                    if case .color(let color) = item.indicator {
                        Circle().fill(color).frame(width: 9, height: 9)
                    }
                    Text(verbatim: item.title)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.settings.primaryText)
                }
            }
            .toggleStyle(.checkbox)
            Spacer(minLength: 8)
            if isReadOnly(item) {
                Label(L10n.tr("sourcecheckboxgroups.read.only", "Read-only"), systemImage: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.settings.secondaryText)
                    .help(L10n.tr("sourcecheckboxgroups.reminders.in.this.list.can.d00b81", "Reminders in this list can be viewed but not changed."))
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
    }
}
