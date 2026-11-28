import FeatureStore
import Foundation
import GeoCore
import MapLibrary
import Tracks
@testable import TrainingAppKit

/// Small files and routes for the map tests (MVP4-101).
enum MapTestSupport {
    /// The area the test maps cover: around Vaduz.
    static let area = BoundingBox(south: 47.0, west: 9.4, north: 47.3, east: 9.7)

    /// A new empty folder in the temporary directory.
    static func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("trainingapp-maps-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A valid, empty store file covering `box`, written to `folder`.
    @discardableResult
    static func storeFile(named name: String = "vaduz.gmk", in folder: URL, box: BoundingBox = area) throws -> URL {
        let writer = FeatureStoreWriter(boundingBox: box, attribution: "© OpenStreetMap contributors, ODbL")
        let url = folder.appendingPathComponent(name)
        try writer.write(to: url)
        return url
    }

    /// A route along a short diagonal from `start`.
    static func route(from start: Coordinate = Coordinate(latitude: 47.10, longitude: 9.50), steps: Int = 10) throws -> Route {
        let points = (0..<steps).map { index in
            TrackPoint(coordinate: Coordinate(latitude: start.latitude + Double(index) * 0.001, longitude: start.longitude + Double(index) * 0.001))
        }
        return try Route(points: points)
    }

    /// A library in a new folder, with its own defaults so the tests don't share a selection.
    @MainActor
    static func library() throws -> (MapLibrary, URL) {
        let root = try folder()
        let defaults = UserDefaults(suiteName: "trainingapp-maps-\(UUID().uuidString)")!
        return (MapLibrary(root: root, defaults: defaults), root)
    }
}
