import Foundation
import GeoCore

/// An area of the world a map is wanted for (MVP4-102): round the athlete, or round a route.
public struct MapArea: Equatable, Sendable {
    /// What the map is called when it is added: "Utrecht", or the route's name.
    public var name: String
    public var box: BoundingBox

    /// The radius of the map round the athlete's position, in kilometres.
    public static let defaultRadiusKilometres = 10.0
    /// The room kept round a route, in kilometres, so a runner who goes a little off the course still has a map.
    public static let routeMarginKilometres = 2.0
    /// The biggest side of an area a phone builds, in kilometres. A bigger one (a long route) needs a ready-made map.
    public static let maximumSideKilometres = 120.0

    public init(name: String, box: BoundingBox) {
        self.name = name
        self.box = box
    }

    /// The map round a position, or `nil` where a circle can't be boxed (at the poles, over the antimeridian).
    public static func around(_ coordinate: Coordinate, radiusKilometres: Double = defaultRadiusKilometres, name: String) -> MapArea? {
        BoundingBox.around(coordinate, radiusKilometres: radiusKilometres).map { MapArea(name: name, box: $0) }
    }

    /// The map for an area with room round it, for a route.
    public static func covering(_ box: BoundingBox, marginKilometres: Double = routeMarginKilometres, name: String) -> MapArea {
        let latitudeMargin = marginKilometres / 111.32
        let middle = (box.south + box.north) / 2
        let longitudeMargin = marginKilometres / (111.32 * max(cos(middle * .pi / 180), 0.01))
        return MapArea(name: name, box: BoundingBox(
            south: max(box.south - latitudeMargin, -85), west: max(box.west - longitudeMargin, -180),
            north: min(box.north + latitudeMargin, 85), east: min(box.east + longitudeMargin, 180)))
    }

    /// The length of the area's sides in kilometres: north to south, and west to east in the middle.
    var sideKilometres: (northSouth: Double, westEast: Double) {
        let middle = (box.south + box.north) / 2
        return ((box.north - box.south) * 111.32, (box.east - box.west) * 111.32 * cos(middle * .pi / 180))
    }

    /// Whether a phone can build a map of this size.
    var fitsPhone: Bool {
        let sides = sideKilometres
        return max(sides.northSouth, sides.westEast) <= Self.maximumSideKilometres
    }

    /// Whether `bounds` holds the whole area.
    func isCovered(by bounds: BoundingBox) -> Bool {
        bounds.south <= box.south && bounds.north >= box.north && bounds.west <= box.west && bounds.east >= box.east
    }
}
