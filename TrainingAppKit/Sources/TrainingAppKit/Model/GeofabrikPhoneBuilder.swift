import Foundation
import GeoCore
import MapBuilder
import Regions

/// Builds a map on the phone with GeoMapKit (MVP4-102): downloads the Geofabrik region files the area needs, then builds only the
/// blocks of the area. The blocks are small (zoom 11, about 10 km), so a build holds a few tens of megabytes and not the gigabyte a
/// block of the Mac's grid takes; the downloaded region files are removed afterwards, as the phone has little room to spare.
actor GeofabrikPhoneBuilder: PhoneMapBuilding {
    /// The block grid of maps built on the phone (the Mac's is 8).
    static let blockZoom = 11
    /// The margin cut round a block so that things near its edge are whole, in degrees (about 2 km).
    static let margin = 0.02

    private let cacheDirectory: URL
    private let downloader: any Downloader
    private let userAgent: String
    private let removesSources: Bool
    private let staleAfter: TimeInterval

    /// What a plan found out, kept until the athlete starts it.
    private struct Prepared {
        var regions: [SourceRegion]
        var downloadPlan: DownloadPlan
    }
    private var prepared: [UUID: Prepared] = [:]

    /// - Parameters:
    ///   - cacheDirectory: Where the region files are kept while they are used.
    ///   - downloader: The network.
    ///   - userAgent: Names the app to the server.
    ///   - removesSources: Whether the region files are deleted after a build. `false` for a folder the app doesn't own (a test).
    ///   - staleAfter: How old a held file may be before the server is asked if it has changed.
    init(
        cacheDirectory: URL, downloader: any Downloader = URLSessionDownloader(userAgent: "TrainingApp"), userAgent: String = "TrainingApp",
        removesSources: Bool = true, staleAfter: TimeInterval = 30 * 24 * 3600
    ) {
        self.cacheDirectory = cacheDirectory
        self.downloader = downloader
        self.userAgent = userAgent
        self.removesSources = removesSources
        self.staleAfter = staleAfter
    }

    private var cache: SourceCache { SourceCache(directory: cacheDirectory, staleAfter: staleAfter) }
    private var catalog: GeofabrikCatalog { GeofabrikCatalog(directory: cacheDirectory, downloader: downloader, staleAfter: staleAfter) }

    func plan(for area: MapArea) async throws -> PhoneBuildPlan {
        guard area.fitsPhone else {
            let sides = area.sideKilometres
            throw MapDownloadError.areaTooLarge(Int(max(sides.northSouth, sides.westEast).rounded()))
        }
        let index = try await catalog.index()
        let regions = try MapBuilder.requiredRegions(
            area: .box(area.box), blockZoom: Self.blockZoom, margin: Self.margin, in: index, cache: cache)
        guard !regions.isEmpty else { throw MapDownloadError.noSourceCoversArea }
        let downloadPlan = try await SourceManager(cache: cache, downloader: downloader)
            .plan(for: RegionSelection(regions: regions, coveredShare: 1))
        let plan = PhoneBuildPlan(
            regionNames: regions.map(\.name), downloadBytes: downloadPlan.hasUnknownSizes ? nil : downloadPlan.bytesToDownload,
            availableBytes: cache.availableBytes())
        prepared[plan.id] = Prepared(regions: regions, downloadPlan: downloadPlan)
        return plan
    }

    func build(_ plan: PhoneBuildPlan, for area: MapArea, into folder: URL, progress: @escaping @Sendable (MapDownloadProgress) -> Void) async throws {
        guard let prepared = prepared[plan.id] else { throw MapDownloadError.noSourceCoversArea }
        defer { self.prepared[plan.id] = nil }
        progress(MapDownloadProgress(phase: .downloading, fraction: prepared.downloadPlan.needsDownload ? 0 : 1))
        // The region files, with the progress of the bytes of all of them together.
        let totals = ProgressTotals(plan: prepared.downloadPlan)
        _ = try await SourceManager(cache: cache, downloader: downloader).fetch(prepared.downloadPlan) { region, bytes, _ in
            progress(MapDownloadProgress(phase: .downloading, fraction: totals.fraction(region: region, bytes: bytes)))
        }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
        let request = BlockRequest(
            area: .box(area.box), output: folder, blockZoom: Self.blockZoom, jobs: 1, margin: Self.margin, profile: .full,
            cacheDirectory: cacheDirectory)
        progress(MapDownloadProgress(phase: .building, fraction: 0))
        _ = try await MapBuilder.buildRegion(
            request, catalog: catalog, downloader: downloader, userAgent: userAgent,
            onProgress: { state in progress(MapDownloadProgress(phase: .building, fraction: state.fraction)) })
        if removesSources {
            for region in prepared.regions { try? cache.remove(regionID: region.id) }
        }
    }

    /// Adds up the bytes of several files as they arrive.
    private final class ProgressTotals: @unchecked Sendable {
        private let lock = NSLock()
        private var held: [String: Int64] = [:]
        private let total: Int64
        private let alreadyHeld: Int64

        init(plan: DownloadPlan) {
            total = plan.items.reduce(0) { $0 + ($1.action == .useCached ? 0 : ($1.size ?? 0)) }
            alreadyHeld = 0
        }

        func fraction(region: String, bytes: Int64) -> Double? {
            lock.lock()
            defer { lock.unlock() }
            held[region] = bytes
            guard total > 0 else { return nil }
            return min(Double(held.values.reduce(0, +)) / Double(total), 1)
        }
    }
}
