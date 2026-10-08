import XCTest
@testable import Shell
@testable import Domain
@testable import Platform

final class WeatherLocationTests: XCTestCase {
    private let krakow = WeatherPlace(name: "Kraków", region: "Lesser Poland", country: "Poland", latitude: 50.06143,
                                      longitude: 19.93658, timeZone: "Europe/Warsaw", placeID: "I1234")

    func testChoiceRoundTripsThroughItsStoredText() {
        for choice in [WeatherLocationChoice.current, .city(krakow)] {
            XCTAssertEqual(WeatherLocationChoice(storageValue: choice.storageValue), choice)
        }
        XCTAssertEqual(WeatherLocationChoice.unset.storageValue, "")
        XCTAssertEqual(WeatherLocationChoice(storageValue: ""), .unset)
        XCTAssertEqual(WeatherLocationChoice(storageValue: "not json"), .unset)
        XCTAssertEqual(WeatherLocationChoice.city(krakow).key, WeatherLocationChoice.city(krakow).key)
        XCTAssertNotEqual(WeatherLocationChoice.city(krakow).key, WeatherLocationChoice.current.key)
    }

    func testNothingStoredMeansNoLocation() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "WeatherLocationTests"))
        defaults.removePersistentDomain(forName: "WeatherLocationTests")
        XCTAssertEqual(GeneralSettings.weatherLocation(defaults: defaults), .unset)
        GeneralSettings.setWeatherLocation(.city(krakow), defaults: defaults)
        XCTAssertEqual(GeneralSettings.weatherLocation(defaults: defaults), .city(krakow))
    }

    func testPlaceLabelsAreHumanReadable() {
        XCTAssertEqual(krakow.title, "Kraków, Lesser Poland, Poland")
        XCTAssertEqual(krakow.detail, "Lesser Poland, Poland")
        let monaco = WeatherPlace(name: "Monaco", region: "Monaco", country: "Monaco", latitude: 43.73, longitude: 7.42)
        XCTAssertEqual(monaco.title, "Monaco", "a region or country repeating the name is left out")
    }

    func testSuggestionSubtitlesSplitIntoRegionAndCountry() {
        XCTAssertEqual(PlaceSearch.regionAndCountry("Greater Poland, Poland").region, "Greater Poland")
        XCTAssertEqual(PlaceSearch.regionAndCountry("Greater Poland, Poland").country, "Poland")
        XCTAssertNil(PlaceSearch.regionAndCountry("Poland").region)
        XCTAssertEqual(PlaceSearch.regionAndCountry("Poland").country, "Poland")
        XCTAssertNil(PlaceSearch.regionAndCountry("").country)
    }
}

/// The weather cache: one request per place at a time, never shared
/// between places, none without a location.
final class CachingWeatherServiceTests: XCTestCase {
    private actor Requests {
        var points: [GeoPoint] = []
        func record(_ point: GeoPoint) { points.append(point) }
    }

    private static func forecast(temperature: Double) -> OpenMeteoForecast {
        let day = OpenMeteoWeatherService.dayKeyFormatter.string(from: .now)
        let json = """
        {"current_weather":{"temperature":\(temperature),"weathercode":0},
        "daily":{"time":["\(day)"],"weathercode":[0],"temperature_2m_max":[\(temperature)],"temperature_2m_min":[\(temperature)],
        "sunrise":["\(day)T06:00"],"sunset":["\(day)T20:00"]},
        "hourly":{"time":[],"temperature_2m":[],"precipitation_probability":[]}}
        """
        return try! JSONDecoder().decode(OpenMeteoForecast.self, from: Data(json.utf8))
    }

    private func service(_ requests: Requests, current: GeoPoint? = nil) -> CachingWeatherService {
        CachingWeatherService(
            fetch: { point in
                await requests.record(point)
                try await Task.sleep(for: .milliseconds(50))
                return Self.forecast(temperature: point.latitude)
            },
            locate: { current }
        )
    }

    func testEachPlaceGetsItsOwnForecastEvenWhenRequestedTogether() async throws {
        let requests = Requests()
        let weather = service(requests)
        let warsaw = WeatherLocationChoice.city(WeatherPlace(name: "Warsaw", latitude: 52.23, longitude: 21.01))
        let krakow = WeatherLocationChoice.city(WeatherPlace(name: "Kraków", latitude: 50.06, longitude: 19.94))
        async let first = weather.fetchWeather(for: .now, at: warsaw)
        async let second = weather.fetchWeather(for: .now, at: krakow)
        let (a, b) = try await (first, second)
        XCTAssertEqual(a?.currentTemperature, 52)
        XCTAssertEqual(b?.currentTemperature, 50)
    }

    func testOnePlaceAskedTwiceAtOnceIsOneRequest() async throws {
        let requests = Requests()
        let weather = service(requests)
        let warsaw = WeatherLocationChoice.city(WeatherPlace(name: "Warsaw", latitude: 52.23, longitude: 21.01))
        async let first = weather.fetchWeather(for: .now, at: warsaw)
        async let second = weather.fetchWeather(for: .now, at: warsaw)
        _ = try await (first, second)
        _ = try await weather.fetchWeather(for: .now, at: warsaw)
        let count = await requests.points.count
        XCTAssertEqual(count, 1)
    }

    func testNoLocationMeansNoRequest() async throws {
        let requests = Requests()
        let weather = service(requests, current: nil)
        let unset = try await weather.fetchWeather(for: .now, at: .unset)
        let unavailable = try await weather.fetchWeather(for: .now, at: .current)
        XCTAssertNil(unset)
        XCTAssertNil(unavailable)
        let count = await requests.points.count
        XCTAssertEqual(count, 0)
    }
}
