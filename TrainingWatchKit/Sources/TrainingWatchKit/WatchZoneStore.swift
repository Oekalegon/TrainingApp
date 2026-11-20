import Foundation
import Observation

/// The zones the watch app uses, from the cache at launch and updated as new ones arrive (WATCH-102).
@MainActor
@Observable
public final class WatchZoneStore {
    /// The athlete's zones, or `nil` while none have been received yet.
    public private(set) var zones: WatchZones?

    private let cache: WatchZonesCache

    public init(cache: WatchZonesCache = WatchZonesCache()) {
        self.cache = cache
        zones = cache.load()
    }

    /// Uses `zones` from now on and keeps them for the next launch.
    public func update(_ zones: WatchZones) {
        guard zones != self.zones else { return }
        self.zones = zones
        cache.save(zones)
    }
}
