import AppKit
import SwiftUI
import Domain
import UI

/// Settings › Intelligence: which model answers Ask. This Mac by
/// default; a provider only when the user picks one and adds their key.
///
/// One way to set the model per provider: from its list when it has one
/// (search, or type an id it doesn't list), otherwise by typing the id and
/// testing it.
package struct IntelligenceSettingsView: View {
    @Environment(\.themePalette) private var theme

    package let store: AssistantSettingsStore

    @State private var listing: ModelListing?
    @State private var isLoading = false
    @State private var isKeyVisible = false
    @State private var isPickerOpen = false
    @State private var test: TestState = .idle

    private enum TestState: Equatable {
        case idle, running
        case finished(AssistantConnectionTest.Outcome)
    }

    private var settings: AssistantSettings { store.settings }

    package var body: some View {
        SettingsPane {
            VStack(alignment: .leading, spacing: 8) {
                assistantGroup
                IntelligencePrivacyNotice(isLocal: !settings.isUsingProvider)
            }
            if let kind = settings.activeProvider { providerGroup(kind) }
            if !settings.alwaysAllowed.isEmpty { alwaysAllowedGroup }
        }
        // Reload the model list when the provider or key changes; the short
        // wait coalesces typing, and a new key cancels the previous fetch.
        .task(id: settings.activeProvider.map { "\($0.rawValue)|\(settings.configuration(for: $0).apiKey)" }) {
            listing = nil
            test = .idle
            guard settings.activeProvider != nil else { return }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await reloadModels()
        }
    }

    // MARK: - This Mac or a provider

    private var assistantGroup: some View {
        SettingsGroup(header: L10n.tr("intelligencesettingsview.assistant", "Assistant")) {
            SettingsPickerRow(
                title: L10n.tr("intelligencesettingsview.answers.from", "Answers from"),
                selection: Binding(
                    get: { settings.activeProvider?.rawValue ?? Self.onThisMac },
                    set: { value in store.update { $0.activeProvider = AssistantProviderKind(rawValue: value) } }
                ),
                options: [(Self.onThisMac, L10n.tr("intelligencesettingsview.this.mac", "This Mac"))] + AssistantProviderKind.allCases.map { ($0.rawValue, $0.displayName) }
            )
            if !settings.isUsingProvider {
                let status = AssistantBackendResolver.onDeviceStatus
                SettingsRow(title: "Apple Intelligence") {
                    statusLabel(color: status == .ready ? theme.settings.granted : theme.settings.pending, text: status.title)
                }
                let model = OnDeviceModelInfo.current(in: AppLocalization.displayLocale)
                if let contextSize = model.contextSize { contextWindowRow(contextSize) }
                if !model.languages.isEmpty { languagesRow(model.languages) }
            }
        }
    }

    private static let onThisMac = "onThisMac"

    // MARK: - Changes made without asking

    /// What "Always Allow …" on a change card remembered, and the way back.
    private var alwaysAllowedGroup: some View {
        SettingsGroup(
            header: L10n.tr("intelligencesettingsview.changes", "Changes"),
            footer: L10n.tr(
                "intelligencesettingsview.dayedge.makes.these.ef3570", "DayEdge makes these changes without asking first. Deleting always asks."
            )
        ) {
            SettingsRow(title: L10n.tr("intelligencesettingsview.always.allowed", "Always allowed")) {
                HStack(spacing: 10) {
                    Text(ChangeKind.allCases.filter(settings.alwaysAllowed.contains).map(\.settingsTitle).joined(separator: ", "))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Button(L10n.tr("intelligencesettingsview.reset", "Reset")) { store.update { $0.alwaysAllowed = [] } }
                }
            }
        }
    }

    // MARK: - The provider: key, then model

    private func providerGroup(_ kind: AssistantProviderKind) -> some View {
        let configuration = settings.configuration(for: kind)
        return SettingsGroup(
            header: kind.displayName,
            footer: L10n.tr("intelligence.provider.key.storage", "Your key is stored on this Mac, in DayEdge's settings file.")
        ) {
            SettingsRow(title: L10n.tr("intelligence.api.key", "API key")) {
                HStack(spacing: 6) {
                    Group {
                        if isKeyVisible {
                            TextField(kind.keyPlaceholder, text: apiKey(kind))
                        } else {
                            SecureField(kind.keyPlaceholder, text: apiKey(kind))
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)

                    Button { isKeyVisible.toggle() } label: {
                        Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(isKeyVisible ? L10n.tr("intelligencesettingsview.hide.key", "Hide key") : L10n.tr("intelligencesettingsview.show.key", "Show key"))
                }
            }

            if hasList(kind) {
                SettingsRow(title: L10n.tr("intelligencesettingsview.status", "Status")) { listStatus(kind, configuration) }
                if let listing, !listing.options.isEmpty {
                    modelMenuRow(kind, listing: listing, selectedID: configuration.modelID)
                    // Only what the provider's catalogue reports for this model.
                    if let tokens = listing.options.first(where: { $0.id == configuration.modelID })?.contextLength {
                        contextWindowRow(tokens)
                    }
                }
            } else {
                SettingsRow(title: L10n.tr("intelligencesettingsview.model.id", "Model id")) {
                    TextField(kind.suggestedModelID, text: modelID(kind))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                }
                SettingsRow(title: L10n.tr("intelligencesettingsview.connection", "Connection")) { testControl(kind, configuration) }
            }
        }
    }

    /// Whether the model is picked from a list: the provider has a live
    /// catalogue or a curated one.
    private func hasList(_ kind: AssistantProviderKind) -> Bool {
        let source = kind.modelSource()
        return source.hasLiveCatalog || !source.curated.isEmpty
    }

    private func modelMenuRow(_ kind: AssistantProviderKind, listing: ModelListing, selectedID: String) -> some View {
        SettingsRow(title: L10n.tr("intelligencesettingsview.model", "Model")) {
            Button {
                isPickerOpen = true
            } label: {
                HStack(spacing: 5) {
                    Text(listing.options.first { $0.id == selectedID }?.title ?? (selectedID.isEmpty ? L10n.tr("intelligencesettingsview.choose", "Choose…") : selectedID))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.settings.secondaryText)
                }
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $isPickerOpen, arrowEdge: .bottom) {
                ModelPickerPopover(
                    options: listing.options,
                    caption: listing.origin == .live ? L10n.tr(
                        "intelligencesettingsview.tool.capable.models.on", "Tool-capable models on \(String(describing: kind.displayName))"
                    ) : L10n.tr(
                        "intelligencesettingsview.suggested.models", "Suggested models"
                    ),
                    selectedID: selectedID,
                    onSelect: { id in
                        setModelID(id, for: kind)
                        isPickerOpen = false
                    }
                )
            }
        }
    }

    // MARK: - Status

    @ViewBuilder
    private func listStatus(_ kind: AssistantProviderKind, _ configuration: ProviderConfiguration) -> some View {
        if configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            HStack(spacing: 8) {
                statusLabel(color: theme.settings.pending, text: L10n.tr("intelligencesettingsview.add.your.key", "Add your key"))
                Link(L10n.tr("intelligencesettingsview.get.a.key", "Get a key…"), destination: kind.keysURL).font(.system(size: 12))
            }
        } else {
            HStack(spacing: 8) {
                let status = listStatusText(kind)
                statusLabel(color: status.color, text: status.text)
                Button { Task { await reloadModels() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .disabled(isLoading)
                    .help(L10n.tr("intelligencesettingsview.check.again", "Check again"))
            }
        }
    }

    private func listStatusText(_ kind: AssistantProviderKind) -> (color: Color, text: String) {
        if isLoading || listing == nil { return (theme.settings.pending, L10n.tr("intelligencesettingsview.checking", "Checking…")) }
        guard let listing else { return (theme.settings.pending, L10n.tr("intelligencesettingsview.checking", "Checking…")) }
        if listing.origin == .live {
            let count = listing.options.count
            return (theme.settings.granted, L10n.tr("intelligence.connected.models", "Connected · \(count) models"))
        }
        let hasSuggestions = !listing.options.isEmpty
        switch listing.liveError {
        case .invalidKey?: return (theme.settings.denied, L10n.tr("intelligencesettingsview.key.not.accepted", "Key not accepted"))
        case .offline?:
            let name = kind.displayName
            let text = hasSuggestions
                ? L10n.tr("intelligence.offline.suggestions", "Couldn't reach \(name) — showing suggested models")
                : L10n.tr("intelligence.offline", "Couldn't reach \(name)")
            return (theme.settings.pending, text)
        case .unexpected?:
            let text = hasSuggestions
                ? L10n.tr("intelligence.models.failed.suggestions", "Couldn't load the model list — showing suggested models")
                : L10n.tr("intelligence.models.failed", "Couldn't load the model list")
            return (theme.settings.pending, text)
        case nil: return (theme.settings.pending, L10n.tr("intelligencesettingsview.suggested.models", "Suggested models"))
        }
    }

    @ViewBuilder
    private func testControl(_ kind: AssistantProviderKind, _ configuration: ProviderConfiguration) -> some View {
        HStack(spacing: 8) {
            switch test {
            case .idle: EmptyView()
            case .running: ProgressView().controlSize(.small)
            case .finished(.works): statusLabel(color: theme.settings.granted, text: L10n.tr("intelligencesettingsview.works", "Works"))
            case .finished(.failed(let reason)): statusLabel(color: theme.settings.denied, text: reason)
            }
            Button(L10n.tr("intelligencesettingsview.test", "Test")) {
                test = .running
                Task { test = .finished(await AssistantConnectionTest.run(kind, configuration: configuration)) }
            }
            .disabled(!configuration.isComplete || test == .running)
        }
    }

    private func statusLabel(color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            StatusDot(color: color)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(theme.settings.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    // MARK: - Editing

    private func apiKey(_ kind: AssistantProviderKind) -> Binding<String> {
        Binding(
            get: { settings.configuration(for: kind).apiKey },
            set: { key in store.update { $0.providers[kind] = ProviderConfiguration(apiKey: key, modelID: $0.configuration(for: kind).modelID) } }
        )
    }

    private func modelID(_ kind: AssistantProviderKind) -> Binding<String> {
        Binding(get: { settings.configuration(for: kind).modelID }, set: { setModelID($0, for: kind) })
    }

    private func setModelID(_ id: String, for kind: AssistantProviderKind) {
        store.update { $0.providers[kind] = ProviderConfiguration(apiKey: $0.configuration(for: kind).apiKey, modelID: id) }
        test = .idle
    }

    private func reloadModels() async {
        guard let kind = settings.activeProvider, hasList(kind) else { return }
        isLoading = true
        listing = await kind.modelSource().listing(apiKey: settings.configuration(for: kind).apiKey)
        isLoading = false
    }

    package init(store: AssistantSettingsStore) {
        self.store = store
    }
}

// MARK: - Model metadata (only what the model or provider reports)

extension IntelligenceSettingsView {
    func contextWindowRow(_ tokens: Int) -> some View {
        SettingsRow(title: L10n.tr("intelligence.context.window", "Context window")) {
            Text(L10n.tr("intelligence.tokens", "\(tokens) tokens"))
                .font(.system(size: 12))
                .foregroundStyle(theme.settings.secondaryText)
        }
    }

    /// "16 languages", opening the list.
    func languagesRow(_ names: [String]) -> some View {
        SettingsRow(title: L10n.tr("intelligence.languages", "Languages")) {
            Menu(L10n.tr("intelligence.language.count", "\(names.count) languages")) {
                ForEach(names, id: \.self) { Text($0) }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}
