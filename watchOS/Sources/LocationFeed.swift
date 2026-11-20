import CoreLocation

/// Streams GPS fixes for an outdoor run. `RunRecorder` forwards them to an `HKWorkoutRouteBuilder`
/// so the route is saved with the workout (WATCH-101).
@MainActor
final class LocationFeed: NSObject, CLLocationManagerDelegate {
    /// Called with each batch of usable fixes (valid and no coarser than 50 m).
    var onUpdate: (([CLLocation]) -> Void)?

    /// Counters for the simulator's debug line: fixes delivered, fixes dropped as too coarse or
    /// invalid, and the last error reported.
    private(set) var receivedCount = 0
    private(set) var droppedCount = 0
    private(set) var lastError: String?

    private let manager = CLLocationManager()
    private var authorizationContinuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
    }

    /// Whether fixes can arrive: the location permission is granted.
    var isAuthorized: Bool {
        manager.authorizationStatus == .authorizedWhenInUse
            || manager.authorizationStatus == .authorizedAlways
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
        let total = locations.count
        Task { @MainActor in
            self.receivedCount += total
            self.droppedCount += total - usable.count
            if !usable.isEmpty { self.onUpdate?(usable) }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.manager.authorizationStatus != .notDetermined else { return }
            self.authorizationContinuation?.resume()
            self.authorizationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let description = "CL \((error as NSError).code)"
        Task { @MainActor in self.lastError = description }
    }
}
