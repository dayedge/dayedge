import SwiftUI

/// A System Settings-style group: an optional header, one rounded card
/// whose rows are separated by hairlines, and an optional footer that
/// explains the group. Callers just list rows; `Group(subviews:)` inserts
/// the dividers between them.
package struct SettingsGroup<Content: View>: View {
    @Environment(\.themePalette) private var theme

    package var header: String?
    package var footer: String?
    @ViewBuilder package var content: () -> Content

    package var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header {
                Text(header)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.settings.primaryText)
                    .padding(.leading, 2)
            }

            VStack(spacing: 0) {
                Group(subviews: content()) { rows in
                    ForEach(rows) { row in
                        row
                        if row.id != rows.last?.id {
                            Rectangle()
                                .fill(theme.settings.divider)
                                .frame(height: 0.5)
                                .padding(.leading, 12)
                        }
                    }
                }
            }
            .background(
                ThemedSurface(role: .nested, fill: theme.settings.groupFill,
                                shape: RoundedRectangle(cornerRadius: AppTheme.Settings.groupRadius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Settings.groupRadius, style: .continuous)
                    .strokeBorder(theme.settings.groupBorder, lineWidth: 0.5)
            )

            if let footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.settings.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
        }
    }

    package init(header: String? = nil, footer: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.header = header
        self.footer = footer
        self.content = content
    }
}

/// One row: label on the left, control on the right.
package struct SettingsRow<Control: View>: View {
    @Environment(\.themePalette) private var theme

    package let title: String
    package var subtitle: String?
    @ViewBuilder package var control: () -> Control

    package var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.settings.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.settings.secondaryText)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
            Spacer(minLength: 12)
            control()
        }
        .padding(.horizontal, 12)
        .frame(minHeight: AppTheme.Settings.rowHeight)
    }

    package init(title: String, subtitle: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.control = control
    }
}

/// A row with a switch — the most common case.
package struct SettingsToggleRow: View {
    @Environment(\.themePalette) private var theme

    package let title: String
    package var subtitle: String?
    @Binding package var isOn: Bool

    package var body: some View {
        SettingsRow(title: title, subtitle: subtitle) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(theme.settings.tint)
        }
    }

    package init(title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }
}

/// A row with a pop-up menu of values.
package struct SettingsPickerRow<Value: Hashable>: View {
    @Environment(\.themePalette) private var theme

    package let title: String
    package var subtitle: String?
    @Binding package var selection: Value
    package let options: [(value: Value, label: String)]

    package init(title: String, subtitle: String? = nil, selection: Binding<Value>, options: [(value: Value, label: String)]) {
        self.title = title
        self.subtitle = subtitle
        self._selection = selection
        self.options = options
    }

    package var body: some View {
        SettingsRow(title: title, subtitle: subtitle) {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .labelsHidden()
            .tint(theme.settings.primaryText)
            // A long menu option must not determine the width of the whole row.
            .frame(maxWidth: 220, alignment: .trailing)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension SettingsPickerRow where Value == Int {
    /// Minute presets, with 0 shown as "Off" (or `zeroLabel`).
    package init(title: String, subtitle: String? = nil, selection: Binding<Int>, minutes: [Int], zeroLabel: String = L10n.tr("settingscomponents.off", "Off")) {
        self.init(
            title: title, subtitle: subtitle, selection: selection,
            options: minutes.map { ($0, $0 == 0 ? zeroLabel : "\($0) min") }
        )
    }
}

/// A small status light: green (ok), red (needs attention), gray (unknown).
package struct StatusDot: View {
    package let color: Color

    package var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: color.opacity(0.6), radius: 3)
    }

    package init(color: Color) {
        self.color = color
    }
}

/// The standard layout for a pane's content column.
package struct SettingsPane<Content: View>: View {
    @ViewBuilder package var content: () -> Content

    package var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            content()
        }
        .frame(maxWidth: AppTheme.Settings.contentMaxWidth, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    package init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
}

extension View {
    /// Dims and disables rows that depend on a switch that is off.
    package func settingsDependent(on isEnabled: Bool) -> some View {
        disabled(!isEnabled).opacity(isEnabled ? 1 : 0.45)
    }
}
