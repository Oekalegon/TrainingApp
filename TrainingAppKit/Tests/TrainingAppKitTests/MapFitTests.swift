import Foundation
import GeoCore
import Testing
@testable import TrainingAppKit

@Suite("Map fit and route map plan (MVP4-101)")
struct MapFitTests {
    private let size = CGSize(width: 400, height: 400)

    @Test("the centre of an area is its middle on the map, and the Mercator maths round-trips")
    func centre() {
        let box = BoundingBox(south: 47.0, west: 9.0, north: 48.0, east: 10.0)
        let centre = MapFit.center(of: box)
        #expect(abs(centre.longitude - 9.5) < 1e-9)
        // On a Mercator map the middle is a little north of the middle in degrees.
        #expect(centre.latitude > 47.5 && centre.latitude < 47.51)
        for latitude in [-60.0, 0, 47.5, 80] {
            #expect(abs(MapFit.latitude(mercatorY: MapFit.mercatorY(latitude)) - latitude) < 1e-9)
        }
    }

    @Test("a bigger area zooms out, the area fits with room round it, and the zoom stays within what the map allows")
    func zoom() {
        let small = BoundingBox(south: 47.10, west: 9.50, north: 47.11, east: 9.51)
        let big = BoundingBox(south: 40, west: 0, north: 50, east: 20)
        let zoomSmall = MapFit.zoom(fitting: small, in: size)
        let zoomBig = MapFit.zoom(fitting: big, in: size)
        #expect(zoomSmall > zoomBig)
        // At that zoom the area's width is within the view, less the padding.
        let pixels = 256 * pow(2, zoomSmall) * (small.east - small.west) / 360
        #expect(pixels <= size.width * (1 - 2 * MapFit.padding) + 1e-6)
        let world = BoundingBox(south: -80, west: -179, north: 80, east: 179)
        #expect(MapFit.zoom(fitting: world, in: size) == MapFit.minimumZoom)
        let tiny = BoundingBox(south: 47.1, west: 9.5, north: 47.1001, east: 9.5001)
        #expect(MapFit.zoom(fitting: tiny, in: size) == MapFit.maximumZoom)
        let point = BoundingBox(south: 47.1, west: 9.5, north: 47.1, east: 9.5)
        #expect(MapFit.zoom(fitting: point, in: size) == MapFit.pointZoom)
    }

    @Test("a tall area is limited by its height and a wide one by its width")
    func orientation() {
        let tall = BoundingBox(south: 40, west: 9.0, north: 50, east: 9.1)
        let wide = BoundingBox(south: 47.0, west: 0, north: 47.1, east: 10)
        let tallZoom = MapFit.zoom(fitting: tall, in: size)
        let wideZoom = MapFit.zoom(fitting: wide, in: size)
        #expect(tallZoom < MapFit.zoom(fitting: BoundingBox(south: 40, west: 9.0, north: 41, east: 9.1), in: size))
        #expect(wideZoom < MapFit.zoom(fitting: BoundingBox(south: 47.0, west: 0, north: 47.1, east: 1), in: size))
    }

    @Test("a distance on the ground is as many points as the map scale says: smaller when zoomed out and north of the equator")
    func accuracyRadius() {
        // At the equator and zoom 0 the world (40 075 km) is 256 points wide.
        #expect(abs(MapFit.points(forMeters: 40_075_016.686, atLatitude: 0, zoom: 0) - 256) < 1e-6)
        let near = MapFit.points(forMeters: 100, atLatitude: 52, zoom: 15)
        let far = MapFit.points(forMeters: 100, atLatitude: 52, zoom: 13)
        #expect(abs(near / far - 4) < 1e-9)
        #expect(MapFit.points(forMeters: 100, atLatitude: 60, zoom: 15) > MapFit.points(forMeters: 100, atLatitude: 0, zoom: 15))
        #expect(MapFit.points(forMeters: 0, atLatitude: 52, zoom: 15) == 0)
    }

    @Test("areas that overlap or touch intersect, and the others don't")
    func intersection() {
        let a = BoundingBox(south: 0, west: 0, north: 1, east: 1)
        #expect(MapFit.intersects(a, BoundingBox(south: 0.5, west: 0.5, north: 2, east: 2)))
        #expect(MapFit.intersects(a, BoundingBox(south: 1, west: 1, north: 2, east: 2)))
        #expect(!MapFit.intersects(a, BoundingBox(south: 1.1, west: 0, north: 2, east: 1)))
        #expect(!MapFit.intersects(a, BoundingBox(south: 0, west: 1.1, north: 1, east: 2)))
    }

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
}
