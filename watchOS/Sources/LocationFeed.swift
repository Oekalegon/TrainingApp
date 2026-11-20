import CoreLocation

/// Streams GPS fixes for an outdoor run. `RunRecorder` forwards them to an `HKWorkoutRouteBuilder`
/// so the route is saved with the workout (WATCH-101).
@MainActor
final class LocationFeed: NSObject, CLLocationManagerDelegate {
    var onUpdate: (([CLLocation]) -> Void)?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Drop invalid fixes and very coarse ones.
        let usable = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 50 }
        guard !usable.isEmpty else { return }
        Task { @MainActor in self.onUpdate?(usable) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
