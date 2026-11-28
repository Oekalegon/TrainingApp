import Foundation
import Testing
import GeoCore
@testable import TrainingAppKit

@MainActor
@Suite("MapLibrary (MVP4-101)")
struct MapLibraryTests {
    @Test("a new library has no maps and nothing selected")
    func empty() throws {
        let (library, _) = try MapTestSupport.library()
        #expect(library.maps.isEmpty)
        #expect(library.selectedMap == nil)
    }

    @Test("adding a map file copies it into the library, selects it, and a second one with the same name gets a number")
    func addCopies() throws {
        let (library, _) = try MapTestSupport.library()
        let source = try MapTestSupport.folder()
        let file = try MapTestSupport.storeFile(in: source)
        let first = library.add([file])
        #expect(first.errors.isEmpty && first.maps == ["vaduz.gmk"])
        #expect(library.maps.map(\.name) == ["vaduz"])
        #expect(library.maps.first?.kind == .file)
        #expect((library.maps.first?.bytes ?? 0) > 0)
        #expect(library.selectedMapID == "vaduz.gmk")
        // The copy is the library's own: the original can go.
        try FileManager.default.removeItem(at: file)
        #expect(throws: Never.self) { _ = try library.open(library.maps[0]) }
        let again = library.add([try MapTestSupport.storeFile(in: source)])
        #expect(again.maps == ["vaduz 2.gmk"])
        #expect(library.maps.map(\.name) == ["vaduz", "vaduz 2"])
        #expect(library.selectedMapID == "vaduz.gmk")
    }

    @Test("what is not a map is refused with a reason, and the others are still added")
    func refuses() throws {
        let (library, _) = try MapTestSupport.library()
        let source = try MapTestSupport.folder()
        let text = source.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: text)
        let broken = source.appendingPathComponent("broken.gmk")
        try Data("not a store".utf8).write(to: broken)
        let noManifest = source.appendingPathComponent("blocks", isDirectory: true)
        try FileManager.default.createDirectory(at: noManifest, withIntermediateDirectories: true)
        let good = try MapTestSupport.storeFile(in: source)
        let result = library.add([text, broken, noManifest, good])
        #expect(result.maps == ["vaduz.gmk"])
        #expect(result.errors.count == 3)
        #expect(result.errors.contains(.notAMap("notes.txt")))
        #expect(result.errors.contains(.noManifest("blocks")))
        #expect(result.errors.contains { if case .unreadable("broken.gmk", _) = $0 { true } else { false } })
        #expect(result.errors.allSatisfy { !($0.errorDescription ?? "").isEmpty })
    }

    @Test("a big file is linked and left where it is, opens through the link, and deleting the link keeps the original")
    func linksBigFile() throws {
        let (library, _) = try MapTestSupport.library()
        library.copyLimit = 10
        let source = try MapTestSupport.folder()
        let file = try MapTestSupport.storeFile(in: source)
        let result = library.add([file])
        #expect(result.errors.isEmpty && result.maps == ["vaduz.maplink"])
        let item = try #require(library.maps.first)
        #expect(item.kind == .linkedFile && item.bytes == nil)
        let opened = try library.open(item)
        #expect(opened.bounds == MapTestSupport.area)
        #expect(opened.attribution.contains("OpenStreetMap"))
        try library.delete(item)
        #expect(library.maps.isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test("a link whose file has gone says so when opened")
    func brokenLink() throws {
        let (library, _) = try MapTestSupport.library()
        library.copyLimit = 10
        let source = try MapTestSupport.folder()
        let file = try MapTestSupport.storeFile(in: source)
        library.add([file])
        try FileManager.default.removeItem(at: file)
        let item = try #require(library.maps.first)
        #expect(throws: MapLibraryError.linkBroken("vaduz")) { _ = try library.open(item) }
    }

    @Test("deleting the selected map moves the selection to another, and the last one leaves none")
    func deleteSelection() throws {
        let (library, _) = try MapTestSupport.library()
        let source = try MapTestSupport.folder()
        library.add([try MapTestSupport.storeFile(named: "a.gmk", in: source), try MapTestSupport.storeFile(named: "b.gmk", in: source)])
        #expect(library.selectedMapID == "a.gmk")
        try library.delete(try #require(library.maps.first))
        #expect(library.selectedMapID == "b.gmk")
        try library.delete(try #require(library.maps.first))
        #expect(library.selectedMapID == nil && library.maps.isEmpty)
    }

    @Test("the selection is kept for the next launch, and a map added outside the app shows up at the next reload")
    func selectionAndReload() throws {
        let root = try MapTestSupport.folder()
        let defaults = UserDefaults(suiteName: "trainingapp-maps-\(UUID().uuidString)")!
        let library = MapLibrary(root: root, defaults: defaults)
        try MapTestSupport.storeFile(named: "a.gmk", in: library.mapsDirectory)
        try MapTestSupport.storeFile(named: "b.gmk", in: library.mapsDirectory)
        #expect(library.maps.isEmpty)
        library.reload()
        #expect(library.maps.map(\.id) == ["a.gmk", "b.gmk"])
        library.selectedMapID = "b.gmk"
        let next = MapLibrary(root: root, defaults: defaults)
        #expect(next.selectedMapID == "b.gmk")
    }

    @Test("opening a map file gives its area and credit")
    func openFile() throws {
        let (library, _) = try MapTestSupport.library()
        library.add([try MapTestSupport.storeFile(in: try MapTestSupport.folder())])
        let opened = try library.open(try #require(library.selectedMap))
        #expect(opened.id == "vaduz.gmk")
        #expect(opened.bounds == MapTestSupport.area)
    }
}
