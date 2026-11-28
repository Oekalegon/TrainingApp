import Foundation

/// Why something could not be added to or opened from the map library (MVP4-101), worded for the athlete.
public enum MapLibraryError: Error, Equatable, LocalizedError {
    /// The file is not a map: only `.gmk` store files and folders of blocks are.
    case notAMap(String)
    /// The folder has no `manifest.json`: it is not a set of blocks.
    case noManifest(String)
    /// A store file or manifest that could not be read.
    case unreadable(String, String)
    /// A linked file or folder that is no longer where it was, or that the app may no longer open.
    case linkBroken(String)
    /// No map is chosen, or the library has none.
    case noMap

    public var errorDescription: String? {
        switch self {
        case .notAMap(let name): "\(name) is not a map. A map is a .gmk file or a folder of blocks."
        case .noManifest(let name): "\(name) has no manifest.json, so it is not a set of blocks."
        case .unreadable(let name, let reason): "\(name) can't be read as a map (\(reason))."
        case .linkBroken(let name): "\(name) is not where it was. Add the map again."
        case .noMap: "There is no map yet."
        }
    }
}
