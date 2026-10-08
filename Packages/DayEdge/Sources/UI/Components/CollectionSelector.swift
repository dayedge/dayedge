import Domain
import SwiftUI

/// One choice in a `CollectionSelector`: a calendar or a reminder list.
package struct CollectionOption: Identifiable, Equatable {
    package let id: String
    package let title: String
    package let color: Color
    /// The account it belongs to ("iCloud", "Exchange").
    package var group: String = ""
}

/// The object's collection, as part of its identity — "● Dom ˅": a small
/// rounded control, quiet until hovered. Events pick a calendar, tasks a
/// list; same chip, same grouped menu, different data.
package struct CollectionSelector: View {
    @Environment(\.themePalette) private var theme

    package let current: CollectionOption
    /// Empty: shown, not changeable.
    package var options: [CollectionOption] = []
    /// A small lock after the name (read-only here), with why.
    package var lockHelp: String?
    package var manageTitle: String?
    package var onManage: (() -> Void)?
    package var onSelect: (String) -> Void = { _ in }

    @State private var isHovering = false

    private var isEditable: Bool { !options.isEmpty }

    package var body: some View {
        Group {
            if isEditable {
                Menu {
                    ForEach(groups, id: \.name) { group in
                        Section(group.name) {
                            ForEach(group.options) { option in
                                DetailCheckButton(title: option.title, isOn: option.id == current.id) { onSelect(option.id) }
                            }
                        }
                    }
                    if let manageTitle, let onManage {
                        Divider()
                        Button(manageTitle, action: onManage)
                    }
                } label: { chip }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .onHover { isHovering = $0 }
            } else {
                chip
            }
        }
        .accessibilityLabel(isEditable ? L10n.tr("collectionselector.calendar", "Calendar, \(String(describing: current.title))") : current.title)
    }

    private var chip: some View {
        HStack(spacing: 5) {
            Circle().fill(current.color).frame(width: 6, height: 6)
            Text(current.title)
                .font(.system(size: 11))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
            if isEditable {
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(theme.content.detailMetadata)
            }
            if let lockHelp {
                Image(systemName: "lock.fill")
                    .font(.system(size: 8.5))
                    .foregroundStyle(theme.content.detailMetadata)
                    .hoverTooltip(lockHelp)
                    .accessibilityLabel(L10n.tr("collectionselector.read.only.in.dayedge", "Read-only in DayEdge"))
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: DetailMetrics.valueRadius, style: .continuous)
                .fill(isHovering && isEditable ? theme.detail.hoverFill : .clear)
        )
        .contentShape(Rectangle())
    }

    private var groups: [(name: String, options: [CollectionOption])] {
        var order: [String] = []
        var byGroup: [String: [CollectionOption]] = [:]
        for option in options {
            if byGroup[option.group] == nil { order.append(option.group) }
            byGroup[option.group, default: []].append(option)
        }
        return order.map { ($0, byGroup[$0] ?? []) }
    }
}

private struct OpenAppSettingsKey: EnvironmentKey {
    static let defaultValue: ((SettingsDestination?) -> Void)? = nil
}

extension EnvironmentValues {
    /// Opens Settings at a pane — "Manage Calendars…", "Manage Lists…".
    /// Nil where the panel isn't the host (the Meeting HUD).
    package var openAppSettings: ((SettingsDestination?) -> Void)? {
        get { self[OpenAppSettingsKey.self] }
        set { self[OpenAppSettingsKey.self] = newValue }
    }
}
