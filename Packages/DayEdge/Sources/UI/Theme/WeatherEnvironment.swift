import Domain
import SwiftUI

private struct WeatherProviderKey: EnvironmentKey {
    static let defaultValue: any WeatherProviding = NoWeatherProvider()
}

extension EnvironmentValues {
    /// Where views fetch weather; the app sets the real one at the panel's root.
    package var weatherProvider: any WeatherProviding {
        get { self[WeatherProviderKey.self] }
        set { self[WeatherProviderKey.self] = newValue }
    }
}
