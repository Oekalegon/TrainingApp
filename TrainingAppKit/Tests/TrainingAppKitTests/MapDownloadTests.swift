import FeatureStore
import Foundation
import GeoCore
import Regions
import Testing
@testable import TrainingAppKit

// MARK: Fakes

/// The server's list of ready-made maps.
private struct FakeHostedCatalog: HostedMapCatalog {
    var result: Result<HostedMap?, any Error> = .success(nil)
    func map(covering area: MapArea) async throws -> HostedMap? { try result.get() }
}

/// The network: "downloads" a store file.
private struct FakeDownloader: Downloader {
    var data: Data
    func metadata(of url: URL, ifNoneMatch etag: String?) async throws -> RemoteMetadata { .info(RemoteFileInfo(size: Int64(data.count))) }
    func download(from url: URL, to file: URL, resumeFrom offset: Int64, ifRange etag: String?, progress: @Sendable (Int64) -> Void) async throws -> RemoteFileInfo {
        try data.write(to: file)
        progress(Int64(data.count))
        return RemoteFileInfo(size: Int64(data.count))
    }
}

/// A builder that plans what it is told and "builds" a set with one block into the folder.
private final class FakePhoneBuilder: PhoneMapBuilding, @unchecked Sendable {
    enum Behaviour { case succeeds, waitsForever, fails }
    var planResult: Result<PhoneBuildPlan, any Error>
    var behaviour: Behaviour
    private(set) var planCalls = 0
    private(set) var buildCalls = 0

    init(plan: Result<PhoneBuildPlan, any Error> = .success(PhoneBuildPlan(regionNames: ["Utrecht"], downloadBytes: 100_000_000, availableBytes: 5_000_000_000)), behaviour: Behaviour = .succeeds) {
        planResult = plan
        self.behaviour = behaviour
    }

    func plan(for area: MapArea) async throws -> PhoneBuildPlan {
        planCalls += 1
        return try planResult.get()
    }

    func build(_ plan: PhoneBuildPlan, for area: MapArea, into folder: URL, progress: @escaping @Sendable (MapDownloadProgress) -> Void) async throws {
        buildCalls += 1
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        progress(MapDownloadProgress(phase: .building, fraction: 0.5))
        switch behaviour {
        case .waitsForever:
            while true { try await Task.sleep(for: .milliseconds(10)) }
        case .fails:
            throw MapDownloadError.noSourceCoversArea
        case .succeeds:
            try Self.writeSet(in: folder, around: area)
        }
    }

    /// A set of one block that covers the area.
    static func writeSet(in folder: URL, around area: MapArea) throws {
        let centre = MapFit.center(of: area.box)
        let tile = try #require(TileID.containing(centre, zoom: 11))
        let writer = FeatureStoreWriter(boundingBox: area.box, attribution: "© OpenStreetMap contributors, ODbL")
        let data = try writer.data()
        let file = "\(tile.x)-\(tile.y).gmk"
        try data.write(to: folder.appendingPathComponent(file))
        let manifest = StoreManifest(
            formatVersion: try FeatureStoreFile(data: data).formatVersion, classifierVersion: 0, storageZoom: 13, blockZoom: 11,
            bands: [.mid, .detail], profile: "full", attribution: "© OpenStreetMap contributors, ODbL",
            blocks: [StoreManifest.Block(x: tile.x, y: tile.y, file: file, bytes: Int64(data.count), builtAt: Date())])
        try manifest.jsonData().write(to: folder.appendingPathComponent("manifest.json"))
    }
}

@MainActor
private struct Setup {
    let library: MapLibrary
    let builtDirectory: URL
    let area = MapArea(name: "Vaduz", box: BoundingBox(south: 47.1, west: 9.5, north: 47.15, east: 9.56))

    init() throws {
        (library, _) = try MapTestSupport.library()
        builtDirectory = try MapTestSupport.folder()
    }

    func model(hosted: FakeHostedCatalog = FakeHostedCatalog(), phone: FakePhoneBuilder = FakePhoneBuilder(), file: Data = Data()) -> MapDownloadModel {
        MapDownloadModel(library: library, hosted: hosted, phone: phone, downloader: FakeDownloader(data: file), builtDirectory: builtDirectory)
    }

    func hostedMap(bytes: Int64 = 100) throws -> (HostedMap, Data) {
        let folder = try MapTestSupport.folder()
        let file = try MapTestSupport.storeFile(in: folder, box: area.box)
        let data = try Data(contentsOf: file)
        return (HostedMap(id: "vaduz", name: "Vaduz", url: URL(string: "https://maps.example.org/vaduz.gmk")!, bytes: Int64(data.count), bounds: area.box), data)
    }
}

/// Waits until the model has left the `running` state.
@MainActor
private func finish(_ model: MapDownloadModel) async {
    for _ in 0..<400 {
        if case .running = model.state {} else { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

// MARK: Tests

@MainActor
@Suite("Map downloads (MVP4-102)")
struct MapDownloadTests {
    @Test("a map the athlete already has that covers the area is used, and nothing is asked")
    func alreadyCovered() async throws {
        let setup = try Setup()
        setup.library.add([try MapTestSupport.storeFile(in: try MapTestSupport.folder(), box: BoundingBox(south: 47.0, west: 9.4, north: 47.3, east: 9.7))])
        let phone = FakePhoneBuilder()
        let model = setup.model(phone: phone)
        await model.prepare(setup.area)
        #expect(model.state == .alreadyCovered(mapName: "vaduz"))
        #expect(phone.planCalls == 0)
        // A map that covers only part of the area is not enough.
        let wide = MapArea(name: "Wide", box: BoundingBox(south: 46.9, west: 9.4, north: 47.4, east: 9.7))
        await model.prepare(wide)
        if case .ready = model.state {} else { Issue.record("a part of the area is not covered") }
    }

    @Test("a ready-made map is preferred, downloaded, put into the library and selected")
    func hosted() async throws {
        let setup = try Setup()
        let (map, data) = try setup.hostedMap()
        let phone = FakePhoneBuilder()
        let model = setup.model(hosted: FakeHostedCatalog(result: .success(map)), phone: phone, file: data)
        await model.prepare(setup.area)
        guard case .ready(let plan) = model.state else { Issue.record("ready"); return }
        #expect(plan.source == .hosted(map) && plan.downloadBytes == map.bytes && plan.fits)
        #expect(phone.planCalls == 0)
        model.start()
        await finish(model)
        #expect(model.state == .done(mapName: "Vaduz"))
        #expect(setup.library.maps.map(\.name) == ["Vaduz"])
        #expect(setup.library.selectedMapID == "Vaduz.gmk")
        #expect(setup.library.maps.first?.kind == .file)
    }

    @Test("a download that is not a map is refused and nothing is added")
    func hostedNotAMap() async throws {
        let setup = try Setup()
        let (map, _) = try setup.hostedMap()
        let model = setup.model(hosted: FakeHostedCatalog(result: .success(map)), file: Data("not a map".utf8))
        await model.prepare(setup.area)
        model.start()
        await finish(model)
        guard case .failed(let text) = model.state else { Issue.record("failed"); return }
        #expect(text.contains("Vaduz"))
        #expect(setup.library.maps.isEmpty)
    }

    @Test("with no ready-made map, or a server that can't be asked, the phone builds one")
    func fallsBackToThePhone() async throws {
        for hosted in [FakeHostedCatalog(result: .success(nil)), FakeHostedCatalog(result: .failure(URLError(.notConnectedToInternet)))] {
            let setup = try Setup()
            let phone = FakePhoneBuilder()
            let model = setup.model(hosted: hosted, phone: phone)
            await model.prepare(setup.area)
            guard case .ready(let plan) = model.state, case .phoneBuild(let build) = plan.source else { Issue.record("phone build"); return }
            #expect(build.regionNames == ["Utrecht"] && phone.planCalls == 1 && plan.downloadBytes == 100_000_000 && plan.fits)
        }
    }

    @Test("a build on the phone ends with the map linked into the library and selected, on the device")
    func phoneBuild() async throws {
        let setup = try Setup()
        let phone = FakePhoneBuilder()
        let model = setup.model(phone: phone)
        await model.prepare(setup.area)
        model.start()
        await finish(model)
        #expect(model.state == .done(mapName: "Vaduz"))
        #expect(phone.buildCalls == 1)
        let item = try #require(setup.library.selectedMap)
        #expect(item.name == "Vaduz" && item.kind == .blocks)
        #expect(FileManager.default.fileExists(atPath: setup.builtDirectory.appendingPathComponent("Vaduz/manifest.json").path))
        // The same area again is covered now.
        await model.prepare(setup.area)
        #expect(model.state == .alreadyCovered(mapName: "Vaduz"))
    }

    @Test("a second map for the same name gets another folder")
    func uniqueFolders() async throws {
        let setup = try Setup()
        let first = setup.model()
        await first.prepare(setup.area)
        first.start()
        await finish(first)
        // Another area with the same name (not covered by the first).
        let other = MapArea(name: "Vaduz", box: BoundingBox(south: 47.5, west: 9.5, north: 47.55, east: 9.56))
        let second = setup.model()
        await second.prepare(other)
        second.start()
        await finish(second)
        #expect(Set(setup.library.maps.map(\.name)) == ["Vaduz", "Vaduz 2"])
    }

    @Test("cancelling a build goes back to the plan and leaves no half-built map")
    func cancel() async throws {
        let setup = try Setup()
        let phone = FakePhoneBuilder(behaviour: .waitsForever)
        let model = setup.model(phone: phone)
        await model.prepare(setup.area)
        model.start()
        for _ in 0..<200 where phone.buildCalls == 0 { try await Task.sleep(for: .milliseconds(10)) }
        model.cancel()
        await finish(model)
        if case .ready = model.state {} else { Issue.record("back to the plan, was \(model.state)") }
        #expect(setup.library.maps.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: setup.builtDirectory.appendingPathComponent("Vaduz").path))
    }

    @Test("a build that fails says why and leaves nothing behind")
    func buildFails() async throws {
        let setup = try Setup()
        let model = setup.model(phone: FakePhoneBuilder(behaviour: .fails))
        await model.prepare(setup.area)
        model.start()
        await finish(model)
        #expect(model.state == .failed(MapDownloadError.noSourceCoversArea.localizedDescription))
        #expect(setup.library.maps.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: setup.builtDirectory.appendingPathComponent("Vaduz").path))
    }

    @Test("a plan that fails, and a download that does not fit, are said so")
    func planFailsAndSpace() async throws {
        let setup = try Setup()
        let failing = setup.model(phone: FakePhoneBuilder(plan: .failure(MapDownloadError.areaTooLarge(300))))
        await failing.prepare(setup.area)
        guard case .failed(let text) = failing.state else { Issue.record("failed"); return }
        #expect(text.contains("300 km"))
        let tight = PhoneBuildPlan(regionNames: ["Spain"], downloadBytes: 900_000_000, availableBytes: 500_000_000)
        let model = setup.model(phone: FakePhoneBuilder(plan: .success(tight)))
        await model.prepare(setup.area)
        guard case .ready(let plan) = model.state else { Issue.record("ready"); return }
        #expect(!plan.fits)
        // Without the room it is not started, even if asked.
        model.start()
        await finish(model)
        guard case .failed(let reason) = model.state else { Issue.record("failed for want of room"); return }
        #expect(reason.contains("not enough room"))
        // Unknown sizes are not a reason to refuse.
        let unknown = MapDownloadPlan(area: setup.area, source: .phoneBuild(PhoneBuildPlan(regionNames: [], downloadBytes: nil, availableBytes: 10)))
        #expect(unknown.fits)
    }

    @Test("reset forgets the plan")
    func reset() async throws {
        let setup = try Setup()
        let model = setup.model()
        await model.prepare(setup.area)
        model.reset()
        #expect(model.state == .idle)
        model.start()
        #expect(model.state == .idle)
    }
}

@Suite("Map areas and the hosted index (MVP4-102)")
struct MapAreaTests {
    @Test("a map round a position is a box of the radius, and a route's map has a margin")
    func boxes() throws {
        let area = try #require(MapArea.around(Coordinate(latitude: 52, longitude: 5), name: "Utrecht"))
        #expect(abs(area.sideKilometres.northSouth - 20) < 0.5 && abs(area.sideKilometres.westEast - 20) < 0.5)
        #expect(area.fitsPhone)
        let route = BoundingBox(south: 52.0, west: 5.0, north: 52.1, east: 5.1)
        let covering = MapArea.covering(route, marginKilometres: 2, name: "Route")
        #expect(covering.box.south < route.south && covering.box.north > route.north && covering.box.west < route.west && covering.box.east > route.east)
        #expect(abs((route.south - covering.box.south) * 111.32 - 2) < 0.01)
        #expect(covering.isCovered(by: covering.box) && !covering.isCovered(by: route))
        #expect(!MapArea(name: "Long", box: BoundingBox(south: 50, west: 5, north: 52, east: 5.1)).fitsPhone)
        #expect(MapArea.around(Coordinate(latitude: 89.99, longitude: 0), name: "Pole") == nil)
        #expect(Set([area.id, covering.id]).count == 2)
    }

    @Test("the hosted index picks the smallest map that covers the whole area, and is checked for its format")
    func index() throws {
        let area = MapArea(name: "A", box: BoundingBox(south: 52.0, west: 5.0, north: 52.1, east: 5.1))
        func map(_ id: String, bytes: Int64, _ box: BoundingBox) -> HostedMap {
            HostedMap(id: id, name: id, url: URL(string: "https://maps.example.org/\(id).gmk")!, bytes: bytes, bounds: box)
        }
        let index = HostedMapIndex(maps: [
            map("country", bytes: 900, BoundingBox(south: 50, west: 3, north: 54, east: 8)),
            map("province", bytes: 90, BoundingBox(south: 51.9, west: 4.8, north: 52.3, east: 5.6)),
            map("elsewhere", bytes: 10, BoundingBox(south: 40, west: 0, north: 41, east: 1)),
            map("partly", bytes: 5, BoundingBox(south: 52.05, west: 5.05, north: 52.5, east: 5.5)),
        ])
        #expect(index.map(covering: area)?.id == "province")
        #expect(HostedMapIndex(maps: []).map(covering: area) == nil)
        let json = """
        {"formatVersion":1,"maps":[{"id":"x","name":"X","url":"https://maps.example.org/x.gmk","bytes":5,
        "bounds":{"south":1,"west":2,"north":3,"east":4},"builtAt":"2026-11-28T00:00:00Z"}]}
        """
        let decoded = try HostedMapIndex.decode(Data(json.utf8))
        #expect(decoded.maps.first?.bounds.north == 3 && decoded.maps.first?.builtAt != nil)
        #expect(throws: (any Error).self) { _ = try HostedMapIndex.decode(Data(#"{"formatVersion":2,"maps":[]}"#.utf8)) }
        #expect(throws: (any Error).self) { _ = try HostedMapIndex.decode(Data("nope".utf8)) }
    }

    @Test("without a server address there is no hosted map, and nothing is asked")
    func noServer() async throws {
        #expect(HostedMapConfiguration.indexURL == nil)
        let catalog = URLSessionHostedMapCatalog(indexURL: nil)
        let area = MapArea(name: "A", box: BoundingBox(south: 52.0, west: 5.0, north: 52.1, east: 5.1))
        #expect(try await catalog.map(covering: area) == nil)
    }

    @Test("a place without a name is named by its coordinates")
    func fallbackName() {
        #expect(PlaceName.fallback(Coordinate(latitude: 52.0, longitude: 5.0)) == "52.00° N 5.00° E")
        #expect(PlaceName.fallback(Coordinate(latitude: -33.9, longitude: -70.7)) == "33.90° S 70.70° W")
    }
}
