import Foundation
import MapKit
import Observation
import Domain

/// The weather location sheet's city search: Apple Maps' completer, limited
/// to towns and cities, a handful of suggestions at a time. Picking one
/// resolves it (one Maps search) to a `WeatherPlace`.
@MainActor
@Observable
final class PlaceSearch: NSObject, MKLocalSearchCompleterDelegate {
    struct Suggestion: Identifiable, Hashable {
        let id: Int
        /// "Poznań".
        let name: String
        /// "Greater Poland, Poland".
        let detail: String
        let completion: MKLocalSearchCompletion

        var title: String { detail.isEmpty ? name : "\(name), \(detail)" }
    }

    static let minimumCharacters = 2
    static let maximumSuggestions = 5

    var query = "" {
        didSet {
            guard query != oldValue else { return }
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count < Self.minimumCharacters {
                completer.cancel()
                suggestions = []
            } else {
                completer.queryFragment = trimmed
            }
        }
    }
    private(set) var suggestions: [Suggestion] = []

    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        completer.addressFilter = MKAddressFilter(including: .locality)
    }

    /// Clears the field and its suggestions.
    func clear() {
        query = ""
        suggestions = []
    }

    /// The suggestion as a place to save; nil if Maps can't place it.
    func resolve(_ suggestion: Suggestion) async -> WeatherPlace? {
        let request = MKLocalSearch.Request(completion: suggestion.completion)
        request.resultTypes = .address
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first,
              let coordinate = Self.coordinate(of: item) else { return nil }
        let parts = Self.regionAndCountry(suggestion.detail)
        return WeatherPlace(name: suggestion.name, region: parts.region, country: parts.country,
                            latitude: coordinate.latitude, longitude: coordinate.longitude,
                            timeZone: item.timeZone?.identifier, placeID: item.identifier?.rawValue)
    }

    /// "Greater Poland, Poland" → region and country; "Poland" → country only.
    nonisolated static func regionAndCountry(_ detail: String) -> (region: String?, country: String?) {
        let parts = detail.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let country = parts.last else { return (nil, nil) }
        return (parts.count > 1 ? parts[0] : nil, country)
    }

    private static func coordinate(of item: MKMapItem) -> CLLocationCoordinate2D? {
        #if HAS_MACOS26_SDK
        if #available(macOS 26, *) { return item.location.coordinate }
        #endif
        return item.placemark.coordinate
    }

    // MARK: MKLocalSearchCompleterDelegate

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            suggestions = completer.results.prefix(Self.maximumSuggestions).enumerated().map { index, completion in
                Suggestion(id: index, name: completion.title, detail: completion.subtitle, completion: completion)
            }
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated { suggestions = [] }
    }
}
