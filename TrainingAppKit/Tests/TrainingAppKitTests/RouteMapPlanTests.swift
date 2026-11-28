import Foundation
import GeoCore
import Testing
@testable import TrainingAppKit

@Suite("Route map plan and place names (MVP4-101)")
struct RouteMapPlanTests {
    private let size = CGSize(width: 400, height: 400)

    @Test("a route on the map is shown, a route off it is said to be outside, and a map that gives no area is tried")
    func plan() {
        let map = BoundingBox(south: 47.0, west: 9.4, north: 47.3, east: 9.7)
        let inside = BoundingBox(south: 47.1, west: 9.5, north: 47.12, east: 9.52)
        let partly = BoundingBox(south: 47.2, west: 9.6, north: 47.5, east: 9.9)
        let outside = BoundingBox(south: 52.0, west: 5.0, north: 52.1, east: 5.1)
        if case .show(let centre, let zoom) = RouteMapPlan.make(routeBounds: inside, mapBounds: map, viewSize: size) {
            #expect(abs(centre.longitude - 9.51) < 1e-9 && zoom > 10)
        } else { Issue.record("a route inside the map is shown") }
        if case .show = RouteMapPlan.make(routeBounds: partly, mapBounds: map, viewSize: size) {} else { Issue.record("a route partly on the map is shown") }
        #expect(RouteMapPlan.make(routeBounds: outside, mapBounds: map, viewSize: size) == .outsideMap)
        if case .show = RouteMapPlan.make(routeBounds: outside, mapBounds: nil, viewSize: size) {} else { Issue.record("an unknown area is tried") }
    }

    @Test("a place without a name is named by its coordinates")
    func fallbackName() {
        #expect(PlaceName.fallback(Coordinate(latitude: 52.0, longitude: 5.0)) == "52.00° N 5.00° E")
        #expect(PlaceName.fallback(Coordinate(latitude: -33.9, longitude: -70.7)) == "33.90° S 70.70° W")
    }
}
