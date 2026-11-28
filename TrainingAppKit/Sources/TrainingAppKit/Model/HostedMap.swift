import Foundation
import GeoCore

/// A ready-made map on a server (MVP4-102): one `.gmk` store file for an area, built once with GeoMapKit and put where the app can
/// download it. A phone fetches a small file and does no building. No server exists yet (see ``HostedMapConfiguration``).
public struct HostedMap: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    /// What the map is called when it is added.
    public let name: String
    public let url: URL
    public let bytes: Int64
    /// The area the file covers.
    public let bounds: BoundingBox
    /// When the file was built from the OpenStreetMap data.
    public let builtAt: Date?

    public init(id: String, name: String, url: URL, bytes: Int64, bounds: BoundingBox, builtAt: Date? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.bytes = bytes
        self.bounds = bounds
        self.builtAt = builtAt
    }
}

/// The list of ready-made maps a server holds: one JSON file, `index.json`, next to the map files.
///
/// ```json
/// { "formatVersion": 1, "maps": [
///   { "id": "utrecht-province", "name": "Utrecht", "url": "https://maps.example.org/utrecht-province.gmk", "bytes": 48000000,
///     "bounds": { "south": 51.9, "west": 4.7, "north": 52.3, "east": 5.6 }, "builtAt": "2026-11-28T00:00:00Z" } ] }
/// ```
public struct HostedMapIndex: Codable, Equatable, Sendable {
    public static let supportedFormatVersion = 1
    public var formatVersion: Int = HostedMapIndex.supportedFormatVersion
    public var maps: [HostedMap]

    public init(maps: [HostedMap]) { self.maps = maps }

    /// The smallest map that holds the whole area, or `nil` when none does.
    func map(covering area: MapArea) -> HostedMap? {
        maps.filter { area.isCovered(by: $0.bounds) }.min { $0.bytes < $1.bytes }
    }

    static func decode(_ data: Data) throws -> HostedMapIndex {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let index = try decoder.decode(HostedMapIndex.self, from: data)
        guard index.formatVersion == supportedFormatVersion else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "format version \(index.formatVersion)"))
        }
        return index
    }
}

/// Where to find ready-made maps (MVP4-102).
public enum HostedMapConfiguration {
    /// The address of the server's `index.json`. `nil` until a server exists: the app then builds maps on the phone.
    public static let indexURL: URL? = nil
}

/// Finds a ready-made map for an area.
public protocol HostedMapCatalog: Sendable {
    /// - Returns: The map that covers the whole area, or `nil` if the server has none (or there is no server).
    /// - Throws: A network or format error; the caller then goes on as if there were none.
    func map(covering area: MapArea) async throws -> HostedMap?
}

/// The catalog on a server: reads its index file and picks from it.
public struct URLSessionHostedMapCatalog: HostedMapCatalog {
    private let indexURL: URL?

    public init(indexURL: URL? = HostedMapConfiguration.indexURL) { self.indexURL = indexURL }

    public func map(covering area: MapArea) async throws -> HostedMap? {
        guard let indexURL else { return nil }
        let (data, response) = try await URLSession.shared.data(from: indexURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try HostedMapIndex.decode(data).map(covering: area)
    }
}
