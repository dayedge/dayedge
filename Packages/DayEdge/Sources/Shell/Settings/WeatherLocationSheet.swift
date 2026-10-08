import MapKit
import SwiftUI
import Domain
import Platform
import UI

/// Settings › General › Calendar: "Weather location   Poznań ›", under
/// Show weather. Opens `WeatherLocationSheet`.
struct WeatherLocationRow: View {
    @Environment(\.themePalette) private var theme
    @AppStorage(GeneralSettings.weatherLocationKey) private var stored = ""
    @State private var isChoosing = false
    private let location = CurrentLocation.shared

    /// "Current Location", the place, or "Choose Location" when there's
    /// nothing usable (never coordinates).
    private var value: String {
        switch WeatherLocationChoice(storageValue: stored) {
        case .unset: L10n.tr("weatherlocationsheet.choose.location", "Choose Location")
        // swiftlint:disable:next void_function_in_ternary - both localization calls return String
        case .current: location.status == .denied ? L10n.tr(
            "weatherlocationsheet.choose.location",
            "Choose Location"
        ) : L10n.tr(
            "weatherlocationsheet.current.location",
            "Current Location"
        )
        case .city(let place): place.name
        }
    }

    var body: some View {
        SettingsRow(title: L10n.tr("weatherlocationsheet.weather.location", "Weather location")) {
            Button { isChoosing = true } label: {
                HStack(spacing: 4) {
                    Text(value)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(theme.settings.secondaryText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $isChoosing) { WeatherLocationSheet() }
    }
}

/// Current Location (permission asked only when picked) or a city found
/// with Apple Maps and confirmed on the map. Edits a draft: Done saves,
/// Cancel and Esc discard.
struct WeatherLocationSheet: View {
    private enum Mode: Hashable { case current, city }

    @Environment(\.themePalette) private var theme
    @Environment(\.dismiss) private var dismiss
    @AppStorage(GeneralSettings.weatherLocationKey) private var stored = ""
    @State private var mode = Mode.city
    @State private var city: WeatherPlace?
    @State private var currentFix: GeoPoint?
    @State private var camera = MapCameraPosition.automatic
    @State private var search = PlaceSearch()
    @State private var highlighted = 0
    @FocusState private var isSearchFocused: Bool
    private let location = CurrentLocation.shared

    /// What Done saves; nil while nothing valid is chosen.
    private var draft: WeatherLocationChoice? {
        switch mode {
        case .current: location.status == .granted ? .current : nil
        case .city: city.map { .city($0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("weatherlocationsheet.weather.location", "Weather Location"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.settings.primaryText)

            Picker(L10n.tr("weatherlocationsheet.weather.location", "Weather location"), selection: Binding(get: { mode }, set: select)) {
                Text(L10n.tr("weatherlocationsheet.current.location", "Current Location")).tag(Mode.current)
                Text(L10n.tr("weatherlocationsheet.choose.city", "Choose City")).tag(Mode.city)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if mode == .city {
                TextField(L10n.tr("weatherlocationsheet.search.city", "Search city…"), text: $search.query)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFocused)
                    .onKeyPress(.downArrow) { moveHighlight(1) }
                    .onKeyPress(.upArrow) { moveHighlight(-1) }
                    .onKeyPress(.return) { acceptHighlighted() }
            }

            map
                .overlay(alignment: .top) { if mode == .city { suggestions } }

            summary

            HStack {
                Spacer()
                Button(L10n.tr("weatherlocationsheet.cancel", "Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.tr("weatherlocationsheet.done", "Done"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft == nil)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear(perform: start)
        .onChange(of: search.suggestions) { _, _ in highlighted = 0 }
        .onChange(of: location.status) { _, status in
            if mode == .current, status == .granted { locate() }
        }
    }

    // MARK: Map

    private var pin: (title: String, coordinate: CLLocationCoordinate2D)? {
        switch mode {
        case .current:
            currentFix.map { (L10n.tr("weatherlocationsheet.current.location", "Current Location"), CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)) }
        case .city:
            city.map { ($0.name, CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)) }
        }
    }

    private var map: some View {
        Map(position: $camera) {
            if let pin { Marker(pin.title, coordinate: pin.coordinate) }
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func center(on coordinate: CLLocationCoordinate2D) {
        withAnimation {
            camera = .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.4, longitudeDelta: 0.4)))
        }
    }

    // MARK: Suggestions (a few, over the map)

    @ViewBuilder
    private var suggestions: some View {
        if isSearchFocused, !search.suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(search.suggestions) { suggestion in
                    Button { Task { await pick(suggestion) } } label: {
                        Text(suggestion.title)
                            .lineLimit(1)
                            .font(.system(size: 13))
                            .foregroundStyle(suggestion.id == highlighted ? Color.white : theme.settings.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(suggestion.id == highlighted ? Color.accentColor : .clear,
                                        in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { if $0 { highlighted = suggestion.id } }
                }
            }
            .padding(4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            .padding(.horizontal, 6)
            .padding(.top, 6)
        }
    }

    private func moveHighlight(_ step: Int) -> KeyPress.Result {
        guard !search.suggestions.isEmpty else { return .ignored }
        highlighted = min(max(highlighted + step, 0), search.suggestions.count - 1)
        return .handled
    }

    /// Return picks the highlighted suggestion while the list shows; else
    /// it falls through to Done.
    private func acceptHighlighted() -> KeyPress.Result {
        guard search.suggestions.indices.contains(highlighted) else { return .ignored }
        let suggestion = search.suggestions[highlighted]
        Task { await pick(suggestion) }
        return .handled
    }

    private func pick(_ suggestion: PlaceSearch.Suggestion) async {
        guard let place = await search.resolve(suggestion) else { return }
        city = place
        search.clear()
        isSearchFocused = false
        center(on: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude))
    }

    // MARK: Summary

    @ViewBuilder
    private var summary: some View {
        switch mode {
        case .current:
            if location.status == .denied {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tr("weatherlocationsheet.location.access.is.off", "Location access is off"))
                        .font(.system(size: 12))
                        .foregroundStyle(theme.settings.secondaryText)
                    Button(L10n.tr("weatherlocationsheet.open.system.settings", "Open System Settings")) { location.openPrivacySettings() }
                }
            } else {
                placeLines(L10n.tr("weatherlocationsheet.current.location", "Current Location"), nil)
            }
        case .city:
            if let city {
                placeLines(city.name, city.detail)
            } else {
                placeLines(" ", nil)
            }
        }
    }

    private func placeLines(_ name: String, _ detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.settings.primaryText)
            Text(detail ?? " ")
                .font(.system(size: 12))
                .foregroundStyle(theme.settings.secondaryText)
        }
        .lineLimit(1)
    }

    // MARK: Choosing

    private func start() {
        switch WeatherLocationChoice(storageValue: stored) {
        case .unset:
            mode = .city
            isSearchFocused = true
        case .current:
            mode = .current
            locate()
        case .city(let place):
            mode = .city
            city = place
            center(on: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude))
        }
    }

    private func select(_ newMode: Mode) {
        mode = newMode
        switch newMode {
        case .current:
            // Asked only now — the user chose Current Location.
            location.requestAccess()
            locate()
        case .city:
            if let city { center(on: CLLocationCoordinate2D(latitude: city.latitude, longitude: city.longitude)) }
            isSearchFocused = true
        }
    }

    /// One fix, to show where Current Location is.
    private func locate() {
        guard location.status == .granted else { return }
        Task {
            guard let fix = await location.coordinate(), mode == .current else { return }
            currentFix = fix
            center(on: CLLocationCoordinate2D(latitude: fix.latitude, longitude: fix.longitude))
        }
    }

    private func save() {
        guard let draft else { return }
        stored = draft.storageValue
        dismiss()
    }
}
