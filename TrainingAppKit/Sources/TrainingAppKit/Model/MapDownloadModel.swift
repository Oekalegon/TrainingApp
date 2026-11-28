import Foundation
import GeoCore
import Observation
import Regions

/// What a download of a map would take and where it comes from (MVP4-102), shown before it starts.
public struct MapDownloadPlan: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        /// A ready-made map file on a server: small, quick.
        case hosted(HostedMap)
        /// Built on this phone from OpenStreetMap region files.
        case phoneBuild(PhoneBuildPlan)
    }

    public let area: MapArea
    public let source: Source

    /// The bytes to download, or `nil` if not known.
    public var downloadBytes: Int64? {
        switch source {
        case .hosted(let map): map.bytes
        case .phoneBuild(let plan): plan.downloadBytes
        }
    }

    public var availableBytes: Int64? {
        if case .phoneBuild(let plan) = source { return plan.availableBytes }
        return nil
    }

    /// Whether the download fits in the free space, with a margin (a built map and its sources are held at once).
    public var fits: Bool {
        guard let needed = downloadBytes, let available = availableBytes else { return true }
        return available >= needed + SourceManager.spareBytes
    }
}

/// Gets a map for an area onto the phone (MVP4-102): the athlete's own library first, then a ready-made map from the server, and when
/// there is none, a build on the phone from OpenStreetMap data. Nothing big is downloaded before ``start()``: ``prepare(_:)`` only asks.
@MainActor
@Observable
public final class MapDownloadModel {
    public enum State: Equatable {
        case idle
        /// Looking for where to get the map.
        case planning
        /// A map in the library already covers the area.
        case alreadyCovered(mapName: String)
        /// What it would take, waiting for the athlete's yes.
        case ready(MapDownloadPlan)
        case running(MapDownloadProgress)
        /// The map is in the library and selected.
        case done(mapName: String)
        case failed(String)
    }

    public private(set) var state: State = .idle
    private let library: MapLibrary
    private let hosted: any HostedMapCatalog
    private let phone: any PhoneMapBuilding
    private let downloader: any Downloader
    /// Where maps built on the phone are kept: on the device, not in iCloud, so a run has its map offline.
    private let builtDirectory: URL
    private var task: Task<Void, Never>?
    private var plan: MapDownloadPlan?

    public init(
        library: MapLibrary, hosted: any HostedMapCatalog, phone: any PhoneMapBuilding, downloader: any Downloader, builtDirectory: URL
    ) {
        self.library = library
        self.hosted = hosted
        self.phone = phone
        self.downloader = downloader
        self.builtDirectory = builtDirectory
    }

    /// Finds where to get the map for an area and what it takes; downloads nothing.
    public func prepare(_ area: MapArea) async {
        state = .planning
        plan = nil
        if let held = library.map(covering: area.box) {
            library.selectedMapID = held.id
            state = .alreadyCovered(mapName: held.name)
            return
        }
        // A server that can't be asked is no server: the phone builds the map.
        if let map = try? await hosted.map(covering: area) {
            ready(MapDownloadPlan(area: area, source: .hosted(map)))
            return
        }
        do {
            let phonePlan = try await phone.plan(for: area)
            ready(MapDownloadPlan(area: area, source: .phoneBuild(phonePlan)))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func ready(_ plan: MapDownloadPlan) {
        self.plan = plan
        state = .ready(plan)
    }

    /// Starts the download the athlete said yes to.
    public func start() {
        guard let plan, task == nil else { return }
        let area = plan.area
        state = .running(MapDownloadProgress(phase: .downloading, fraction: nil))
        task = Task { [weak self] in
            guard let self else { return }
            do {
                switch plan.source {
                case .hosted(let map): try await self.downloadHosted(map)
                case .phoneBuild(let phonePlan): try await self.build(phonePlan, area: area)
                }
            } catch is CancellationError {
                self.state = .ready(plan)
            } catch {
                self.state = .failed(error.localizedDescription)
            }
            self.task = nil
        }
    }

    /// Stops a download that is running. What was downloaded is kept, so a second try goes on.
    public func cancel() { task?.cancel() }

    /// Back to the start, for a new area.
    public func reset() {
        task?.cancel()
        task = nil
        plan = nil
        state = .idle
    }

    // MARK: Sources

    private func downloadHosted(_ map: HostedMap) async throws {
        let part = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gmk")
        defer { try? FileManager.default.removeItem(at: part) }
        _ = try await downloader.download(from: map.url, to: part, resumeFrom: 0, ifRange: nil) { [weak self] bytes in
            let fraction = map.bytes > 0 ? min(Double(bytes) / Double(map.bytes), 1) : nil
            Task { @MainActor in self?.state = .running(MapDownloadProgress(phase: .downloading, fraction: fraction)) }
        }
        try Task.checkCancellation()
        let id = try library.install(fileAt: part, named: map.name)
        library.selectedMapID = id
        state = .done(mapName: map.name)
    }

    private func build(_ phonePlan: PhoneBuildPlan, area: MapArea) async throws {
        if let needed = phonePlan.downloadBytes, let available = phonePlan.availableBytes, available < needed {
            throw MapDownloadError.notEnoughSpace(needed: needed, available: available)
        }
        let folder = uniqueFolder(named: area.name)
        do {
            try await phone.build(phonePlan, for: area, into: folder) { [weak self] progress in
                Task { @MainActor in
                    // A late report must not overwrite the end of the work.
                    if case .running = self?.state { self?.state = .running(progress) }
                }
            }
            try Task.checkCancellation()
            let result = library.add([folder])
            guard let id = result.maps.first else {
                throw result.errors.first ?? MapDownloadError.emptyResult
            }
            library.selectedMapID = id
            state = .done(mapName: area.name)
        } catch {
            // A half-built map is of no use: the blocks that were done are rebuilt next time, the source files are kept.
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    private func uniqueFolder(named name: String) -> URL {
        let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespaces)
        var candidate = builtDirectory.appendingPathComponent(safe.isEmpty ? "Map" : safe, isDirectory: true)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) || library.maps.contains(where: { $0.name == candidate.lastPathComponent }) {
            candidate = builtDirectory.appendingPathComponent("\(safe) \(number)", isDirectory: true)
            number += 1
        }
        return candidate
    }
}
