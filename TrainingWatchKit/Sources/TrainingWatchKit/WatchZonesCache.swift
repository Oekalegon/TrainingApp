import Foundation

/// Keeps the last zones the watch received, so a run can start with the phone out of reach.
public struct WatchZonesCache: Sendable {
    private let cache: JSONDefaultsCache<WatchZones>

    public init(defaults: UserDefaults = .standard) {
        cache = JSONDefaultsCache(key: "watchZones.v1", defaults: defaults)
    }

    /// The cached zones, or `nil` when none were received yet or the cache can't be read.
    public func load() -> WatchZones? { cache.load() }

    /// Replaces the cached zones.
    public func save(_ zones: WatchZones) { cache.save(zones) }
}
