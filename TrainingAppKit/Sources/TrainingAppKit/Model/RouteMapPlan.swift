import Foundation
import GeoCore

/// What a map of a route shows (MVP4-101): decided from the route's area and the area the map covers, so the view model's choice
/// is tested without a map file.
enum RouteMapPlan: Equatable {
    /// The map covers the route (at least in part): where to look and how far to zoom.
    case show(center: Coordinate, zoom: Double)
    /// The route is entirely outside the map: say so, and not an empty map.
    case outsideMap

    /// - Parameters:
    ///   - routeBounds: The area of the route.
    ///   - mapBounds: The area the map covers, or `nil` when the map doesn't say (then it is tried).
    ///   - viewSize: The size of the map view in points, for the zoom.
    static func make(routeBounds: BoundingBox, mapBounds: BoundingBox?, viewSize: CGSize) -> RouteMapPlan {
        if let mapBounds, !MapFit.intersects(routeBounds, mapBounds) { return .outsideMap }
        return .show(center: MapFit.center(of: routeBounds), zoom: MapFit.zoom(fitting: routeBounds, in: viewSize))
    }
}
