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

    private var authorizationContinuation: CheckedContinuation<Void, Never>?

    var isAuthorized: Bool {
        manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
    }

    /// A short description of the permission, for the simulator's debug line.
    var authorizationDescription: String {
        switch manager.authorizationStatus {
        case .notDetermined: "not asked"
        case .restricted: "restricted"
        case .denied: "denied"
        case .authorizedAlways, .authorizedWhenInUse: "allowed"
        @unknown default: "unknown"
        }
    }

    /// Asks for location access and returns once the user has answered, so the prompt comes before
    /// the run and not over it. Returns at once when it has already been answered.
    func requestAuthorization() async {
        guard manager.authorizationStatus == .notDetermined else { return }
        await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    func start() {
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

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.manager.authorizationStatus != .notDetermined else { return }
            self.authorizationContinuation?.resume()
            self.authorizationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
