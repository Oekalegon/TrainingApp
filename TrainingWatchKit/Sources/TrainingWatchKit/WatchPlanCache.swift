import Foundation

/// Keeps the last plan the watch received, so a run can start with the phone out of reach.
public struct WatchPlanCache: Sendable {
    private let cache: JSONDefaultsCache<WatchPlan>

    public init(defaults: UserDefaults = .standard) {
        cache = JSONDefaultsCache(key: "watchPlan.v1", defaults: defaults)
    }

    /// The cached plan, or `nil` when none was received yet or the cache can't be read.
    public func load() -> WatchPlan? { cache.load() }

    /// Replaces the cached plan.
    public func save(_ plan: WatchPlan) { cache.save(plan) }
}
