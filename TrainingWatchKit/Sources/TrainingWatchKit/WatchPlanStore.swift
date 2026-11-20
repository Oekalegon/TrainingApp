import Foundation
import Observation

/// Keeps the last plan the watch received, so a run can start with the phone out of reach
/// (the watch app has to work on its own during a run).
public struct WatchPlanCache: Sendable {
    private static let key = "watchPlan.v1"

    // `UserDefaults` is thread-safe but not `Sendable`; the cache only reads and writes one key.
    private nonisolated(unsafe) let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The cached plan, or `nil` when none was received yet or the cache can't be read.
    public func load() -> WatchPlan? {
        defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(WatchPlan.self, from: $0) }
    }

    /// Replaces the cached plan.
    public func save(_ plan: WatchPlan) {
        guard let data = try? JSONEncoder().encode(plan) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

/// The plan the watch app shows, from the cache at launch and updated as new ones arrive (WATCH-103).
@MainActor
@Observable
public final class WatchPlanStore {
    /// The upcoming planned workouts, or `nil` while none have been received yet. Empty means the
    /// phone said nothing is planned.
    public private(set) var plan: WatchPlan?

    private let cache: WatchPlanCache

    public init(cache: WatchPlanCache = WatchPlanCache()) {
        self.cache = cache
        plan = cache.load()
    }

    /// Uses `plan` from now on.
    ///
    /// - Parameters:
    ///   - plan: The upcoming planned workouts.
    ///   - persist: Whether to keep them for the next launch; `false` for test plans that
    ///     shouldn't outlive the run.
    public func update(_ plan: WatchPlan, persist: Bool = true) {
        guard plan != self.plan else { return }
        self.plan = plan
        if persist { cache.save(plan) }
    }

    /// The workouts planned for today, earliest first; empty when there are none or no plan has
    /// arrived (``plan`` tells those apart).
    ///
    /// - Parameters:
    ///   - now: The current time, injected so tests can pin the day.
    ///   - calendar: Decides where the day starts; the watch's own, so "today" is where the athlete is.
    public func today(asOf now: Date = .now, calendar: Calendar = .current) -> [WatchPlannedWorkout] {
        plan?.workouts(on: now, calendar: calendar) ?? []
    }
}
