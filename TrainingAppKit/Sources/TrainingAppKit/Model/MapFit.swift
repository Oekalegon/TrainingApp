import Foundation
import GeoCore

/// Where to put a map and how far to zoom so an area fits the view (MVP4-101): Web Mercator maths on the area's bounds.
enum MapFit {
    /// The tile size the map view's zoom is measured in (256-point tiles).
    static let tileSize = 256.0
    /// The room kept round the area, as a share of the view.
    static let padding = 0.15
    /// The zoom for an area with no size (one point), and the furthest the app zooms in for a route.
    static let pointZoom = 15.0
    static let maximumZoom = 17.0
    static let minimumZoom = 2.0

    /// A Web Mercator y between 0 (the north pole's edge) and 1, for a latitude in degrees.
    static func mercatorY(_ latitude: Double) -> Double {
        let radians = max(min(latitude, 85.05), -85.05) * .pi / 180
        return (1 - log(tan(radians) + 1 / cos(radians)) / .pi) / 2
    }

    /// The latitude in degrees of a Web Mercator y.
    static func latitude(mercatorY y: Double) -> Double {
        atan(sinh(.pi * (1 - 2 * y))) * 180 / .pi
    }

    /// The middle of an area, in the map's own projection, so a tall area is centred on what is seen.
    static func center(of box: BoundingBox) -> Coordinate {
        let y = (mercatorY(box.south) + mercatorY(box.north)) / 2
        return Coordinate(latitude: latitude(mercatorY: y), longitude: (box.west + box.east) / 2)
    }

    /// The zoom at which an area fills a view of `size` points, with ``padding`` round it.
    static func zoom(fitting box: BoundingBox, in size: CGSize) -> Double {
        let width = max(size.width, 1) * (1 - 2 * padding)
        let height = max(size.height, 1) * (1 - 2 * padding)
        let lonShare = (box.east - box.west) / 360
        let latShare = abs(mercatorY(box.south) - mercatorY(box.north))
        guard lonShare > 1e-9 || latShare > 1e-9 else { return pointZoom }
        let byWidth = lonShare > 1e-9 ? log2(width / (tileSize * lonShare)) : .infinity
        let byHeight = latShare > 1e-9 ? log2(height / (tileSize * latShare)) : .infinity
        return min(max(min(byWidth, byHeight), minimumZoom), maximumZoom)
    }

    /// Whether two areas overlap (touching counts).
    static func intersects(_ a: BoundingBox, _ b: BoundingBox) -> Bool {
        a.south <= b.north && b.south <= a.north && a.west <= b.east && b.west <= a.east
    }

    /// How many points a distance on the ground is at a latitude and zoom (256-point tiles): the radius of the accuracy circle round
    /// the position.
    static func points(forMeters meters: Double, atLatitude latitude: Double, zoom: Double) -> Double {
        let metersPerPoint = 40_075_016.686 * cos(latitude * .pi / 180) / (tileSize * pow(2, zoom))
        return meters / max(metersPerPoint, 1e-9)
    }
}
