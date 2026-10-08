import Foundation

/// A place weather is shown for, as Apple Maps named it.
package struct WeatherPlace: Codable, Hashable, Sendable {
    /// "Poznań" — what Settings shows.
    package var name: String
    /// "Greater Poland".
    package var region: String?
    /// "Poland".
    package var country: String?
    package var latitude: Double
    package var longitude: Double
    /// IANA identifier, when known.
    package var timeZone: String?
    /// Apple Maps' identifier for the place, when it has one.
    package var placeID: String?

    package init(name: String, region: String? = nil, country: String? = nil, latitude: Double, longitude: Double,
                 timeZone: String? = nil, placeID: String? = nil) {
        self.name = name
        self.region = region
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.timeZone = timeZone
        self.placeID = placeID
    }

    /// "Greater Poland, Poland" — what tells two places of the same name apart.
    package var detail: String {
        [region, country].compactMap { $0 }.filter { !$0.isEmpty && $0 != name }.joined(separator: ", ")
    }

    /// "Poznań, Greater Poland, Poland".
    package var title: String { detail.isEmpty ? name : "\(name), \(detail)" }
}

/// Where weather comes from (Settings › General › Weather location).
/// Nothing chosen means no weather — never a guessed place.
package enum WeatherLocationChoice: Codable, Hashable, Sendable {
    case unset
    /// The Mac's approximate location, fixed once when needed.
    case current
    case city(WeatherPlace)

    /// Stable for one choice: a city by its coordinates.
    package var key: String {
        switch self {
        case .unset: "unset"
        case .current: "current"
        case .city(let place): "city:\(place.latitude),\(place.longitude)"
        }
    }

    /// As stored in UserDefaults (JSON text, so `@AppStorage` can watch it).
    package var storageValue: String {
        guard self != .unset, let data = try? JSONEncoder().encode(self) else { return "" }
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    /// From `storageValue`; anything unreadable is `.unset`.
    package init(storageValue: String) {
        guard !storageValue.isEmpty,
              let choice = try? JSONDecoder().decode(Self.self, from: Data(storageValue.utf8)) else {
            self = .unset
            return
        }
        self = choice
    }
}

extension GeneralSettings {
    /// The weather location (`WeatherLocationChoice.storageValue`). Kept when
    /// weather is turned off.
    package static let weatherLocationKey = "com.dayedge.general.weatherLocation"

    package static func weatherLocation(defaults: UserDefaults = .standard) -> WeatherLocationChoice {
        WeatherLocationChoice(storageValue: defaults.string(forKey: weatherLocationKey) ?? "")
    }

    package static func setWeatherLocation(_ choice: WeatherLocationChoice, defaults: UserDefaults = .standard) {
        defaults.set(choice.storageValue, forKey: weatherLocationKey)
    }
}
