import Foundation

/// Keeps the last zones the watch received, so a run can start with the phone out of reach
/// (the watch app has to work on its own during a run).
public struct WatchZonesCache: Sendable {
    private static let key = "watchZones.v1"

    // `UserDefaults` is thread-safe but not `Sendable`; the cache only reads and writes one key.
    private nonisolated(unsafe) let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The cached zones, or `nil` when none were received yet or the cache can't be read.
    public func load() -> WatchZones? {
        defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(WatchZones.self, from: $0) }
    }

    /// Replaces the cached zones.
    public func save(_ zones: WatchZones) {
        guard let data = try? JSONEncoder().encode(zones) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
