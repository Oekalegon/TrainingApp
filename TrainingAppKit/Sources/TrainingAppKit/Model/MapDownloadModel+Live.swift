import Foundation
import Regions

extension MapDownloadModel {
    /// The model the app uses: a ready-made map from the server when it has one, and a build on the phone when not.
    ///
    /// Maps built on the phone and the region files they are built from are kept in the app's own storage, on the device and out of
    /// backups (they can be made again): a run's map is there without a network. In the simulator, `-mapSourceCache <folder>` reads the
    /// region files from a folder of the Mac (GeoMapKit's own cache, for example), and never deletes them.
    @MainActor
    static func live(library: MapLibrary) -> MapDownloadModel {
        let root = URL.applicationSupportDirectory.appendingPathComponent("Maps", isDirectory: true)
        let built = root.appendingPathComponent("Built", isDirectory: true)
        var sources = root.appendingPathComponent("Sources", isDirectory: true)
        var removesSources = true
        var staleAfter: TimeInterval = 30 * 24 * 3600
        #if targetEnvironment(simulator)
        if let path = UserDefaults.standard.string(forKey: "mapSourceCache"), !path.isEmpty {
            sources = URL(fileURLWithPath: path, isDirectory: true)
            removesSources = false
            staleAfter = .infinity
        }
        #endif
        for folder in [built, sources] {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        excludeFromBackup(built)
        if removesSources { excludeFromBackup(sources) }
        let downloader = URLSessionDownloader(userAgent: "TrainingApp")
        return MapDownloadModel(
            library: library, hosted: URLSessionHostedMapCatalog(),
            phone: GeofabrikPhoneBuilder(cacheDirectory: sources, downloader: downloader, removesSources: removesSources, staleAfter: staleAfter),
            downloader: downloader, builtDirectory: built)
    }

    /// Keeps a folder out of iCloud and device backups: what is in it can be downloaded again.
    private static func excludeFromBackup(_ folder: URL) {
        var folder = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
    }
}
