import Foundation
import GeoCore
import MapLibrary
import Testing
import Tracks
@testable import TrainingAppKit

@MainActor
@Suite("RouteMapViewModel (MVP4-101)")
struct RouteMapViewModelTests {
    private let size = CGSize(width: 400, height: 400)

    @Test("without a map it says there is none")
    func noMap() throws {
        let (library, _) = try MapTestSupport.library()
        let model = RouteMapViewModel(route: try MapTestSupport.route(), library: library)
        if case .idle = model.state {} else { Issue.record("starts idle") }
        model.load(viewSize: size)
        if case .noMap = model.state {} else { Issue.record("no map") }
    }

    @Test("a route on the selected map is ready, centred on the route, and keeps its overlay when loaded again")
    func ready() throws {
        let (library, _) = try MapTestSupport.library()
        library.add([try MapTestSupport.storeFile(in: try MapTestSupport.folder())])
        let model = RouteMapViewModel(route: try MapTestSupport.route(), library: library)
        model.load(viewSize: size)
        guard case .ready(let first) = model.state else { Issue.record("ready"); return }
        #expect(first.map.id == "vaduz.gmk")
        #expect(abs(first.center.longitude - model.route.boundingBox.west - (model.route.boundingBox.east - model.route.boundingBox.west) / 2) < 1e-9)
        #expect(first.zoom > 10 && first.zoom <= 17)
        // A new size changes where to look and how far to zoom; the map and the drawn overlay stay.
        model.load(viewSize: CGSize(width: 200, height: 200))
        guard case .ready(let second) = model.state else { Issue.record("ready again"); return }
        #expect(second.map === first.map && second.overlay === first.overlay)
        #expect(second.zoom < first.zoom)
    }

    @Test("a route off the map says which map it is not on")
    func outside() throws {
        let (library, _) = try MapTestSupport.library()
        library.add([try MapTestSupport.storeFile(in: try MapTestSupport.folder())])
        let amsterdam = try MapTestSupport.route(from: Coordinate(latitude: 52.37, longitude: 4.89))
        let model = RouteMapViewModel(route: amsterdam, library: library)
        model.load(viewSize: size)
        guard case .outsideMap(let name) = model.state else { Issue.record("outside"); return }
        #expect(name == "vaduz")
    }

    @Test("another selected map opens that map, and a map that can't be opened is reported")
    func switchAndFail() throws {
        let (library, _) = try MapTestSupport.library()
        let source = try MapTestSupport.folder()
        library.add([try MapTestSupport.storeFile(named: "a.gmk", in: source), try MapTestSupport.storeFile(named: "b.gmk", in: source)])
        let model = RouteMapViewModel(route: try MapTestSupport.route(), library: library)
        model.load(viewSize: size)
        library.selectedMapID = "b.gmk"
        model.load(viewSize: size)
        guard case .ready(let ready) = model.state else { Issue.record("ready"); return }
        #expect(ready.map.id == "b.gmk")
        // The file is damaged after it was added.
        try Data("damaged".utf8).write(to: library.mapsDirectory.appendingPathComponent("b.gmk"))
        library.selectedMapID = "a.gmk"
        try Data("damaged".utf8).write(to: library.mapsDirectory.appendingPathComponent("a.gmk"))
        model.load(viewSize: size)
        guard case .failed(let text) = model.state else { Issue.record("failed"); return }
        #expect(text.contains("a"))
    }
}
