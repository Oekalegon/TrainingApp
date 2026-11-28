import Foundation

/// Why a map could not be downloaded or built (MVP4-102), worded for the athlete.
public enum MapDownloadError: Error, Equatable, LocalizedError {
    /// The area is too big for the phone to build, and no ready-made map covers it.
    case areaTooLarge(Int)
    /// No source file covers the area (the open sea, a pole).
    case noSourceCoversArea
    /// The disk has too little room.
    case notEnoughSpace(needed: Int64, available: Int64)
    /// The downloaded file is not a map.
    case notAMap(String)
    /// The build finished with nothing in it.
    case emptyResult

    public var errorDescription: String? {
        switch self {
        case .areaTooLarge(let kilometres):
            "That area is \(kilometres) km across, too big to build on the phone. A ready-made map is needed for a route this long."
        case .noSourceCoversArea: "There is no map data for this area."
        case .notEnoughSpace(let needed, let available):
            "There is not enough room: \(ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)) is needed and "
                + "\(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)) is free."
        case .notAMap(let name): "\(name) was downloaded but it is not a map."
        case .emptyResult: "The map came out empty. Try a bigger area."
        }
    }
}
