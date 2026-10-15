import Foundation

/// What a "new workout" notification does (MVP2-121), apart from the HealthKit plumbing that
/// delivers it, so the order can be tested.
enum ArrivedWorkoutImport {
    /// Imports the new workouts (which links them to their plans, MVP2-120), then puts the Watch
    /// schedule right again, since a done plan's entry is kept and the window moves on (MVP2-116),
    /// and finally tells the UI, if there is one, so it refreshes its caches.
    ///
    /// The Watch sync is awaited: the system keeps a background-launched app awake only until the
    /// observer is told the work is finished. A failed import doesn't stop the sync or the
    /// notification, and nothing is thrown: like pull-to-refresh, the next launch, refresh or
    /// notification catches up.
    ///
    /// - Parameters:
    ///   - refresher: Runs the import.
    ///   - watchSync: Syncs the Watch afterwards; `nil` where WorkoutKit isn't available.
    ///   - today: The current time, passed to both, for tests to pin.
    ///   - notify: Runs last.
    @MainActor
    static func run(
        refresher: any ActivityRefreshing,
        watchSync: WatchScheduleSync?,
        asOf today: Date,
        notify: @MainActor () async -> Void
    ) async {
        try? await refresher.refreshActivities(asOf: today)
        await watchSync?.requestSync(asOf: today).value
        await notify()
    }
}
