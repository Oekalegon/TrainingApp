import Foundation
import Testing
@testable import TrainingAppKit

@Suite("GPXRouteLoader (MVP4-101)")
struct GPXRouteLoaderTests {
    private func gpx(_ body: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">\(body)</gpx>
        """.utf8)
    }

    private let track = """
    <trk><name>Morning</name><trkseg>
    <trkpt lat="47.10" lon="9.50"><ele>450</ele></trkpt>
    <trkpt lat="47.11" lon="9.51"><ele>460</ele></trkpt>
    <trkpt lat="47.12" lon="9.52"><ele>455</ele></trkpt>
    </trkseg></trk>
    """

    @Test("a route is read first, a track when there is no route")
    func routeOrTrack() throws {
        let fromTrack = try GPXRouteLoader.route(from: gpx(track))
        #expect(fromTrack.points.count == 3 && fromTrack.name == "Morning")
        let rte = """
        <rte><name>Course</name>
        <rtept lat="47.20" lon="9.60"/><rtept lat="47.21" lon="9.61"/>
        </rte>
        """
        let both = try GPXRouteLoader.route(from: gpx(track + rte))
        #expect(both.points.count == 2 && both.name == "Course")
    }

    @Test("a file with nothing to show, or that is not GPX, is refused with a reason")
    func refuses() {
        #expect(throws: GPXRouteLoader.LoadError.noRoute) { _ = try GPXRouteLoader.route(from: gpx("")) }
        #expect(throws: GPXRouteLoader.LoadError.noRoute) {
            _ = try GPXRouteLoader.route(from: gpx(#"<trk><trkseg><trkpt lat="47.1" lon="9.5"/></trkseg></trk>"#))
        }
        #expect(throws: (any Error).self) { _ = try GPXRouteLoader.route(from: Data("not xml".utf8)) }
        #expect(GPXRouteLoader.LoadError.noRoute.errorDescription?.isEmpty == false)
    }
}
