import Foundation
import Observation

/// The plan the watch app shows, from the cache at launch and updated as new ones arrive (WATCH-103).
@MainActor
@Observable
public final class WatchPlanStore {
    /// How long a plan counts as fresh. The phone sends again whenever its app is active and at
    /// least every few hours, so a plan older than this means the phone hasn't been opened.
    public static let freshFor: TimeInterval = 24 * 3600

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

    /// A note for the screen when the plan is old, such as "Plan from 3 days ago: open TrainingApp
    /// to update"; `nil` when there is no plan or it is fresh (see ``freshFor``).
    ///
    /// - Parameter now: The current time, injected so tests can pin the age.
    public func staleNote(asOf now: Date = .now) -> String? {
        guard let plan else { return nil }
        let age = now.timeIntervalSince(plan.sentAt)
        guard age > Self.freshFor else { return nil }
        let days = Int(age / 86400)
        return days >= 2 ? "Plan from \(days) days ago: open TrainingApp to update"
            : "Plan from yesterday: open TrainingApp to update"
    }
}
