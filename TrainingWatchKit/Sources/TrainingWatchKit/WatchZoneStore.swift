import Foundation
import Observation

/// The zones the watch app uses, from the cache at launch and updated as new ones arrive (WATCH-102).
@MainActor
@Observable
public final class WatchZoneStore {
    /// The athlete's zones, or `nil` while none have been received yet.
    public private(set) var zones: WatchZones?
    /// The bands of ``zones``, worked out once per update, for asking which zone a heart rate is in
    /// on every reading; `nil` while there are no zones or they can't be resolved.
    public private(set) var bands: ZoneBands?

    private let cache: WatchZonesCache

    public init(cache: WatchZonesCache = WatchZonesCache()) {
        self.cache = cache
        zones = cache.load()
        bands = zones.flatMap { ZoneBands(zones: $0) }
    }

    /// Uses `zones` from now on.
    ///
    /// - Parameters:
    ///   - zones: The athlete's zones.
    ///   - persist: Whether to keep them for the next launch; `false` for test zones that
    ///     shouldn't outlive the run.
    public func update(_ zones: WatchZones, persist: Bool = true) {
        guard zones != self.zones else { return }
        self.zones = zones
        bands = ZoneBands(zones: zones)
        if persist { cache.save(zones) }
    }
}
