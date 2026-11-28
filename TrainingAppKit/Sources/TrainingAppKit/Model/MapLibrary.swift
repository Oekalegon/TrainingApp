import FeatureStore
import Foundation
import GeoCore
import Observation

/// The maps the athlete has stored, and which of them is shown (MVP4-101).
///
/// Everything is a file in one folder, `Maps` in the app's Documents, which the Files app can see: a map is a `.gmk` store file
/// that was copied in, or a `.maplink` file that holds a bookmark to a folder of blocks (or a very big file) that stays where
/// it is. The list is read from the folder, so a file added or removed outside the app shows up at the next ``reload()``. Only
/// the selection is kept elsewhere (`UserDefaults`). The kit's own demo app keeps its maps the same way, so a map made with
/// its tools can be added here.
@MainActor
@Observable
public final class MapLibrary {
    /// The maps, by name.
    public private(set) var maps: [MapItem] = []
    /// The map that is shown, as the id of its item.
    public var selectedMapID: String? {
        didSet { defaults.set(selectedMapID, forKey: Keys.map) }
    }

    public let mapsDirectory: URL
    private let defaults: UserDefaults

    private enum Keys { static let map = "selectedMap" }

    /// The extension of the files that link to a folder of blocks or to a big file.
    static let linkExtension = "maplink"

    /// A store file bigger than this is linked and not copied: a copy would take long on the main thread and use the space twice.
    var copyLimit: Int64 = 100_000_000

    /// What ``add(_:)`` did.
    public struct AddResult: Equatable {
        /// The ids of the maps that were added, in the order of the items given.
        public var maps: [String] = []
        /// One error for each item that could not be added; the others were added.
        public var errors: [MapLibraryError] = []
    }

    /// Opens the library in a folder: the Documents of the app, or another folder (tests use a new one).
    public init(root: URL = URL.documentsDirectory, defaults: UserDefaults = .standard) {
        mapsDirectory = root.appendingPathComponent("Maps", isDirectory: true)
        self.defaults = defaults
        try? FileManager.default.createDirectory(at: mapsDirectory, withIntermediateDirectories: true)
        selectedMapID = defaults.string(forKey: Keys.map)
        reload()
    }

    // MARK: Reading the folder

    /// Reads the folder again, and keeps the selection on a map that is still there (the first map when none is chosen).
    public func reload() {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: mapsDirectory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])) ?? []
        maps = urls.compactMap { url -> MapItem? in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            let ext = url.pathExtension.lowercased()
            guard ext == "gmk" || ext == Self.linkExtension else { return nil }
            let kind: MapItem.Kind = ext == "gmk" ? .file : (Self.linkKind(at: url) == .file ? .linkedFile : .blocks)
            return MapItem(
                id: url.lastPathComponent, name: url.deletingPathExtension().lastPathComponent, kind: kind,
                bytes: ext == "gmk" ? Int64(values.fileSize ?? 0) : nil, date: values.contentModificationDate ?? .distantPast)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if let selectedMapID, !maps.contains(where: { $0.id == selectedMapID }) { self.selectedMapID = nil }
        if selectedMapID == nil, let first = maps.first { selectedMapID = first.id }
    }

    func url(of map: MapItem) -> URL { mapsDirectory.appendingPathComponent(map.id) }

    /// The map that is shown, if there is one.
    public var selectedMap: MapItem? { maps.first { $0.id == selectedMapID } }

    // MARK: Adding

    /// Adds what the athlete picked: a `.gmk` store file (copied, or linked when it is big) or a folder of blocks (linked).
    @discardableResult
    public func add(_ urls: [URL]) -> AddResult {
        var result = AddResult()
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                result.maps.append(try add(url))
            } catch let error as MapLibraryError {
                result.errors.append(error)
            } catch {
                result.errors.append(.unreadable(url.lastPathComponent, error.localizedDescription))
            }
        }
        reload()
        return result
    }

    /// Adds one item and returns the file name it has in the library.
    private func add(_ url: URL) throws -> String {
        let name = url.lastPathComponent
        let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        if isFolder {
            let manifest = url.appendingPathComponent("manifest.json")
            guard FileManager.default.fileExists(atPath: manifest.path) else { throw MapLibraryError.noManifest(name) }
            do { _ = try StoreSet(manifestURL: manifest) } catch { throw MapLibraryError.unreadable(name, "\(error)") }
            return try writeLink(to: url, kind: .folder, name: name)
        }
        guard url.pathExtension.lowercased() == "gmk" else { throw MapLibraryError.notAMap(name) }
        do { _ = try FeatureStoreFile(contentsOf: url) } catch { throw MapLibraryError.unreadable(name, "\(error)") }
        let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        let base = url.deletingPathExtension().lastPathComponent
        if size > copyLimit { return try writeLink(to: url, kind: .file, name: base) }
        let target = uniqueURL(name: base, ext: "gmk")
        try FileManager.default.copyItem(at: url, to: target)
        return target.lastPathComponent
    }

    private func writeLink(to url: URL, kind: Link.Kind, name: String) throws -> String {
        let target = uniqueURL(name: name, ext: Self.linkExtension)
        try JSONEncoder().encode(Link(bookmark: try Self.bookmark(for: url), kind: kind)).write(to: target, options: .atomic)
        return target.lastPathComponent
    }

    /// A file name in the library that is not taken: `name.ext`, or `name 2.ext` and so on.
    func uniqueURL(name: String, ext: String) -> URL {
        var candidate = mapsDirectory.appendingPathComponent(name).appendingPathExtension(ext)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = mapsDirectory.appendingPathComponent("\(name) \(number)").appendingPathExtension(ext)
            number += 1
        }
        return candidate
    }

    // MARK: Removing

    /// Removes a map from the library: a copied file is deleted, a link is removed and the folder or file it led to is left alone.
    public func delete(_ map: MapItem) throws {
        try FileManager.default.removeItem(at: url(of: map))
        reload()
    }

    // MARK: Opening

    /// Opens a map for drawing. A linked folder or file is opened with the access the bookmark gives, held until the result is released.
    ///
    /// - Throws: ``MapLibraryError`` for a link that leads nowhere any more or a file that can't be read.
    public func open(_ map: MapItem) throws -> OpenedMap {
        switch map.kind {
        case .file:
            do {
                let file = try FeatureStoreFile(contentsOf: url(of: map))
                return OpenedMap(id: map.id, source: file, bounds: file.boundingBox)
            } catch { throw MapLibraryError.unreadable(map.name, "\(error)") }
        case .blocks, .linkedFile:
            guard let target = resolve(map) else { throw MapLibraryError.linkBroken(map.name) }
            let accessing = target.startAccessingSecurityScopedResource()
            let held = accessing ? [target] : []
            do {
                if map.kind == .blocks {
                    let set = try StoreSet(manifestURL: target.appendingPathComponent("manifest.json"))
                    return OpenedMap(id: map.id, source: set, bounds: set.boundingBox, accessed: held)
                }
                let file = try FeatureStoreFile(contentsOf: target)
                return OpenedMap(id: map.id, source: file, bounds: file.boundingBox, accessed: held)
            } catch {
                if accessing { target.stopAccessingSecurityScopedResource() }
                throw MapLibraryError.unreadable(map.name, "\(error)")
            }
        }
    }

    /// The folder or file a link in the library leads to, or `nil` if it cannot be resolved. No access is started.
    func resolve(_ map: MapItem) -> URL? {
        guard let link = try? JSONDecoder().decode(Link.self, from: Data(contentsOf: url(of: map))) else { return nil }
        var stale = false
        return (try? URL(resolvingBookmarkData: link.bookmark, options: Self.resolutionOptions, relativeTo: nil, bookmarkDataIsStale: &stale))?
            .standardizedFileURL.resolvingSymlinksInPath()
    }

    // MARK: Links

    private struct Link: Codable {
        enum Kind: String, Codable { case folder, file }
        var bookmark: Data
        /// What the bookmark leads to; a link written before big files were linked has none and is a folder.
        var kind: Kind?
    }

    private static func linkKind(at url: URL) -> Link.Kind {
        ((try? JSONDecoder().decode(Link.self, from: Data(contentsOf: url)))?.kind) ?? .folder
    }

    private static func bookmark(for url: URL) throws -> Data {
        #if os(macOS)
        try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }

    private static var resolutionOptions: URL.BookmarkResolutionOptions {
        #if os(macOS)
        .withSecurityScope
        #else
        []
        #endif
    }
}
