import SwiftUI
import UI

/// Picks a model from a provider's list — whatever that list knows: a row
/// shows the name (or just the id), the id beneath only when there is a
/// name, and context/price only when present. The search field filters
/// (↑ ↓ to move, Return to choose) and also takes any model id the list
/// doesn't have ("Use “…”"), so there's one way to set the model.
package struct ModelPickerPopover: View {
    @Environment(\.themePalette) private var theme

    package let options: [ModelOption]
    /// What the list is ("Tool-capable models on OpenRouter", "Suggested models").
    package let caption: String
    package let selectedID: String
    package let onSelect: (String) -> Void

    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var isFilterFocused: Bool

    private var visible: [ModelOption] { ModelOption.filter(options, query: query) }

    /// A typed id that isn't in the list (ids have no spaces).
    private var customID: String? {
        let id = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !id.contains(" "), !options.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    /// Everything Return and the arrows move through: matches, then the typed id.
    private var choices: [String] { visible.map(\.id) + (customID.map { [$0] } ?? []) }

    package var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L10n.tr("modelpickerpopover.search.or.enter.a.model.id", "Search, or enter a model id"), text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($isFilterFocused)
                .onSubmit(chooseHighlighted)
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .onChange(of: query) { _, _ in highlighted = 0 }

            if choices.isEmpty {
                Text(L10n.tr("modelpickerpopover.no.models.match", "No models match “\(String(describing: query))”."))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.settings.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ScrollViewReader { proxy in
                    ThemedScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(visible.enumerated()), id: \.element.id) { index, option in
                                row(option, isHighlighted: index == highlighted)
                                    .id(option.id)
                            }
                            if let customID {
                                customRow(customID, isHighlighted: highlighted == visible.count)
                                    .id(customID)
                            }
                        }
                    }
                    .onChange(of: highlighted) { _, index in
                        guard choices.indices.contains(index) else { return }
                        proxy.scrollTo(choices[index])
                    }
                }
                .frame(maxHeight: 340)
            }

            Text(query.isEmpty ? caption : L10n.tr("models.visible.count", "\(caption) · \(visible.count) of \(options.count)"))
                .font(.system(size: 11))
                .foregroundStyle(theme.settings.secondaryText)
        }
        .padding(12)
        .frame(width: 440)
        .onAppear { isFilterFocused = true }
    }

    private func row(_ option: ModelOption, isHighlighted: Bool) -> some View {
        Button { onSelect(option.id) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(option.id == selectedID ? 1 : 0)
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.title)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.settings.primaryText)
                        .lineLimit(1)
                    if option.name?.isEmpty == false {
                        Text(option.id)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.settings.secondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let detail = option.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.settings.secondaryText)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHighlighted ? theme.secondaryControl.hover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A model id the list doesn't have, used as typed.
    private func customRow(_ id: String, isHighlighted: Bool) -> some View {
        Button { onSelect(id) } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).opacity(0)
                Text(L10n.tr("modelpickerpopover.use", "Use “\(String(describing: id))”"))
                    .font(.system(size: 13))
                    .foregroundStyle(theme.settings.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHighlighted ? theme.secondaryControl.hover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func move(_ delta: Int) {
        guard !choices.isEmpty else { return }
        highlighted = min(max(highlighted + delta, 0), choices.count - 1)
    }

    private func chooseHighlighted() {
        guard choices.indices.contains(highlighted) else { return }
        onSelect(choices[highlighted])
    }
}
