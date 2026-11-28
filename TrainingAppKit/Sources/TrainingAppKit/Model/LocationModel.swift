import CoreLocation
import GeoCore
import Observation

/// Where the athlete is, for the dot on the map and "centre on me" (MVP4-101). The app starts it while the map is shown and stops
/// it when the map is not, so the map costs no battery in the background; it only ever asks for "when in use".
@MainActor
@Observable
final class LocationModel: NSObject, CLLocationManagerDelegate {
    /// The last position, or `nil` before the first one.
    private(set) var coordinate: Coordinate?
    /// How far off the position can be, in metres (the radius of the circle drawn round the dot), or `nil` before the first one.
    private(set) var accuracy: Double?
    /// Whether the athlete said no, so the button can say what to do.
    private(set) var denied = false
    /// Whether the position is being followed: it was asked for and is allowed.
    private(set) var isFollowing = false

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    /// Asks for permission the first time, and then follows the position.
    func start() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            followIfAllowed()
        }
    }

    /// Follows the position when it is allowed; never asks.
    private func followIfAllowed() {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            denied = true
            isFollowing = false
        case .notDetermined:
            break
        default:
            denied = false
            isFollowing = true
            manager.startUpdatingLocation()
        }
    }

    /// Stops following, to save the battery when the map is not shown.
    func stop() {
        manager.stopUpdatingLocation()
        isFollowing = false
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.followIfAllowed() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let coordinate = Coordinate(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude)
        let accuracy = last.horizontalAccuracy >= 0 ? last.horizontalAccuracy : nil
        Task { @MainActor in
            self.coordinate = coordinate
            self.accuracy = accuracy
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // No position yet is not an error for the athlete: the dot appears once there is one.
    }
}
