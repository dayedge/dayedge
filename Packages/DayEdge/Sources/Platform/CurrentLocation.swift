import AppKit
import CoreLocation
import Domain
import Observation

/// The Mac's approximate location, for weather only: one reduced-accuracy
/// fix when weather asks, never continuous tracking. Permission is asked
/// only by `requestAccess()` — when the user picks Current Location.
@MainActor
@Observable
package final class CurrentLocation: NSObject, CLLocationManagerDelegate {
    package static let shared = CurrentLocation()

    package private(set) var status: SourceAccessStatus = .notDetermined

    @ObservationIgnored private let manager = CLLocationManager()
    /// The last fix this run, for when a new one fails.
    @ObservationIgnored private var lastFix: GeoPoint?
    @ObservationIgnored private var waiting: [CheckedContinuation<GeoPoint?, Never>] = []
    @ObservationIgnored private var timeout: Task<Void, Never>?

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
        status = Self.status(manager.authorizationStatus)
    }

    /// Asks for permission if it hasn't been asked yet.
    package func requestAccess() {
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    /// System Settings › Privacy & Security › Location Services.
    package func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else { return }
        NSWorkspace.shared.open(url)
    }

    /// One fix, rounded to about a kilometre; the last one if this fails;
    /// nil without permission.
    package func coordinate() async -> GeoPoint? {
        guard status == .granted else { return nil }
        if waiting.isEmpty {
            manager.requestLocation()
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                self?.finish(with: nil)
            }
        }
        return await withCheckedContinuation { waiting.append($0) }
    }

    private func finish(with fix: GeoPoint?) {
        timeout?.cancel()
        timeout = nil
        if let fix { lastFix = fix }
        let result = fix ?? lastFix ?? manager.location.map { GeoPoint($0.coordinate) }
        let continuations = waiting
        waiting = []
        continuations.forEach { $0.resume(returning: result) }
    }

    nonisolated private static func status(_ authorization: CLAuthorizationStatus) -> SourceAccessStatus {
        switch authorization {
        case .notDetermined: .notDetermined
        case .denied, .restricted: .denied
        default: .granted
        }
    }

    // MARK: CLLocationManagerDelegate

    nonisolated package func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let fix = locations.last.map { GeoPoint($0.coordinate) }
        MainActor.assumeIsolated { finish(with: fix) }
    }

    nonisolated package func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { finish(with: nil) }
    }

    nonisolated package func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = Self.status(manager.authorizationStatus)
        MainActor.assumeIsolated { self.status = status }
    }
}

/// A coordinate rounded to two decimals (about a kilometre): enough for
/// weather, and a stable cache key.
package struct GeoPoint: Hashable, Sendable {
    package let latitude: Double
    package let longitude: Double

    package init(latitude: Double, longitude: Double) {
        self.latitude = (latitude * 100).rounded() / 100
        self.longitude = (longitude * 100).rounded() / 100
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
