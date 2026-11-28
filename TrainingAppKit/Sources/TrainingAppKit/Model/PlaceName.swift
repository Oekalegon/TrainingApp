import CoreLocation
import Foundation
import GeoCore

/// A name for the map round a position (MVP4-102): the town, or the coordinates when the geocoder has no answer.
enum PlaceName {
    static func name(near coordinate: Coordinate) async -> String {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        if let place = placemarks?.first, let name = place.locality ?? place.subAdministrativeArea ?? place.administrativeArea {
            return name
        }
        return fallback(coordinate)
    }

    /// "52.00° N 5.00° E".
    static func fallback(_ coordinate: Coordinate) -> String {
        String(
            format: "%.2f° %@ %.2f° %@", abs(coordinate.latitude), coordinate.latitude >= 0 ? "N" : "S", abs(coordinate.longitude),
            coordinate.longitude >= 0 ? "E" : "W")
    }
}

