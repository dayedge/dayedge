import Foundation
import Domain

/// Wraps `OpenMeteoWeatherService` with an in-memory, app-lifetime cache so
/// repeated requests — the day view being paged back and forth, every
/// visible agenda day header wanting its own weather glyph — don't each
/// trigger a network call.
///
/// One Open-Meteo request already returns the *entire* 7-day forecast
/// window (daily + hourly), so this caches that whole payload per
/// location: the first call for any date in range pays for one network
/// round trip, and every other date of that place — for at least an hour —
/// is served from memory. Cache and in-flight requests are both keyed by
/// location, so a response is never shared between two places.
package actor CachingWeatherService: WeatherProviding {
    package static let shared = CachingWeatherService(
        fetch: { try await OpenMeteoWeatherService().fetchRawForecast(latitude: $0.latitude, longitude: $0.longitude) },
        locate: { await CurrentLocation.shared.coordinate() }
    )

    private let fetch: @Sendable (GeoPoint) async throws -> OpenMeteoForecast
    private let locate: @Sendable () async -> GeoPoint?
    private let timeToLive: TimeInterval

    private var cache: [GeoPoint: CachedForecast] = [:]
    private var inFlight: [GeoPoint: Task<OpenMeteoForecast, Error>] = [:]

    package init(fetch: @escaping @Sendable (GeoPoint) async throws -> OpenMeteoForecast,
                 locate: @escaping @Sendable () async -> GeoPoint?,
                 timeToLive: TimeInterval = 3600) {
        self.fetch = fetch
        self.locate = locate
        self.timeToLive = timeToLive
    }

    package func fetchWeather(for date: Date, at location: WeatherLocationChoice) async throws -> WeatherSummary? {
        guard let point = await point(for: location) else { return nil }
        let forecast = try await forecast(at: point)
        return OpenMeteoWeatherService.summary(from: forecast, for: date)
    }

    /// Where the choice points: a city's saved place, the current location
    /// when available, nothing when unset.
    private func point(for location: WeatherLocationChoice) async -> GeoPoint? {
        switch location {
        case .unset: nil
        case .current: await locate()
        case .city(let place): GeoPoint(latitude: place.latitude, longitude: place.longitude)
        }
    }

    private func forecast(at point: GeoPoint) async throws -> OpenMeteoForecast {
        if let cached = cache[point], Date().timeIntervalSince(cached.fetchedAt) < timeToLive {
            return cached.forecast
        }
        // Concurrent callers for the same place (several agenda day headers
        // mounting at once) await one request instead of each firing their own.
        if let running = inFlight[point] {
            return try await running.value
        }
        let fetch = fetch
        let task = Task { try await fetch(point) }
        inFlight[point] = task
        defer { inFlight[point] = nil }
        let forecast = try await task.value
        cache[point] = CachedForecast(forecast: forecast, fetchedAt: Date())
        return forecast
    }
}

private struct CachedForecast {
    let forecast: OpenMeteoForecast
    let fetchedAt: Date
}
