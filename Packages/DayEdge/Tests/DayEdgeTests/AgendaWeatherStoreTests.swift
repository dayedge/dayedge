import XCTest
@testable import Shell
@testable import Domain
@testable import Agenda

@MainActor
final class AgendaWeatherStoreTests: XCTestCase {
    private struct StubWeatherProvider: WeatherProviding {
        var summaries: [Date: WeatherSummary] = [:]
        var shouldThrow = false
        /// Only answers for this location.
        var location = WeatherLocationChoice.current

        func fetchWeather(for date: Date, at location: WeatherLocationChoice) async throws -> WeatherSummary? {
            if shouldThrow { throw URLError(.badServerResponse) }
            guard location == self.location else { return nil }
            return summaries[Calendar.autoupdatingCurrent.startOfDay(for: date)]
        }
    }

    private func summary() -> WeatherSummary {
        WeatherSummary(
            currentTemperature: 20, condition: "Clear", symbolName: "sun.max",
            highTemperature: 24, lowTemperature: 15, sunrise: "06:00", sunset: "20:00",
            sunriseHour: 6, sunsetHour: 20, hourly: [], currentHour: nil
        )
    }

    private func section(daysFromToday: Int) -> AgendaDaySection {
        let calendar = Calendar.autoupdatingCurrent
        let date = calendar.date(byAdding: .day, value: daysFromToday, to: calendar.startOfDay(for: .now))!
        return AgendaDaySection(date: date, events: [])
    }

    func testRefreshPopulatesWeatherForSectionsInsideForecastWindow() async {
        let inWindow = section(daysFromToday: 1)
        let provider = StubWeatherProvider(summaries: [inWindow.date: summary()])
        let store = AgendaWeatherStore(provider: provider)

        await store.refresh(for: [inWindow], at: .current)

        XCTAssertEqual(store.weatherBySection[inWindow.id]?.currentTemperature, 20)
    }

    func testRefreshSkipsSectionsOutsideForecastWindow() async {
        let outOfWindow = section(daysFromToday: 30)
        let provider = StubWeatherProvider(summaries: [outOfWindow.date: summary()])
        let store = AgendaWeatherStore(provider: provider)

        await store.refresh(for: [outOfWindow], at: .current)

        XCTAssertNil(store.weatherBySection[outOfWindow.id])
    }

    func testRefreshLeavesEntryAbsentWhenProviderThrows() async {
        let inWindow = section(daysFromToday: 1)
        let provider = StubWeatherProvider(shouldThrow: true)
        let store = AgendaWeatherStore(provider: provider)

        await store.refresh(for: [inWindow], at: .current)

        XCTAssertNil(store.weatherBySection[inWindow.id])
    }

    func testANewLocationNeverKeepsThePreviousPlacesWeather() async {
        let inWindow = section(daysFromToday: 1)
        let store = AgendaWeatherStore(provider: StubWeatherProvider(summaries: [inWindow.date: summary()]))
        await store.refresh(for: [inWindow], at: .current)
        XCTAssertNotNil(store.weatherBySection[inWindow.id])

        let warsaw = WeatherPlace(name: "Warsaw", country: "Poland", latitude: 52.23, longitude: 21.01)
        await store.refresh(for: [inWindow], at: .city(warsaw))
        XCTAssertNil(store.weatherBySection[inWindow.id], "the stub has nothing for Warsaw: the old entry must be gone")
    }
}
