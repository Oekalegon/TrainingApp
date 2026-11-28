import Foundation

/// What building a map on the phone takes, shown to the athlete before it starts (MVP4-102).
public struct PhoneBuildPlan: Equatable, Sendable {
    public let id: UUID
    /// The source regions whose files are needed, for example "Utrecht".
    public let regionNames: [String]
    /// What would be downloaded: the files the phone doesn't have yet, or `nil` if a server didn't say.
    public let downloadBytes: Int64?
    /// The free space on the phone, or `nil` if unknown.
    public let availableBytes: Int64?

    public init(id: UUID = UUID(), regionNames: [String], downloadBytes: Int64?, availableBytes: Int64?) {
        self.id = id
        self.regionNames = regionNames
        self.downloadBytes = downloadBytes
        self.availableBytes = availableBytes
    }
}

/// Where a download or build is: shown with a progress bar.
public struct MapDownloadProgress: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// Downloading the map file, or the OpenStreetMap data it is built from.
        case downloading
        /// Building the map from the data, on the phone.
        case building
    }

    public var phase: Phase
    /// How far the phase is, 0 to 1, or `nil` when it isn't known.
    public var fraction: Double?

    public init(phase: Phase, fraction: Double?) {
        self.phase = phase
        self.fraction = fraction
    }
}

/// Builds a map for an area on the phone from OpenStreetMap data (MVP4-102): the fallback when no ready-made map exists.
public protocol PhoneMapBuilding: Sendable {
    /// Finds the source files the area needs and what they would take, downloading nothing.
    func plan(for area: MapArea) async throws -> PhoneBuildPlan

    /// Downloads what the plan needs and builds the map into a new folder.
    ///
    /// - Parameters:
    ///   - plan: A plan this builder made.
    ///   - area: The area the plan was made for.
    ///   - folder: The folder for the map's blocks and manifest; it is created.
    ///   - progress: Called as the work goes on, from any thread.
    /// - Throws: `CancellationError` when the task is cancelled; the files already downloaded are kept for another try.
    func build(_ plan: PhoneBuildPlan, for area: MapArea, into folder: URL, progress: @escaping @Sendable (MapDownloadProgress) -> Void) async throws
}
