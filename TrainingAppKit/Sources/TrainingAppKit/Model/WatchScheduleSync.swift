import Foundation
import TrainingCore

/// Keeps the Watch's scheduled workouts in step with the plans (MVP2-55): the next 7 days of
/// planned workouts are put on the Watch, and entries that no longer belong there are removed.
///
/// WorkoutKit never wakes the app, so the window only moves forward when the app runs. The app
/// calls ``sync(asOf:)`` whenever it becomes active (`AppTabView`), which covers launch and the
/// window rolling over at midnight. Each run compares what should be on the Watch with what is, so
/// it can run any number of times: scheduling an unchanged plan is a no-op.
///
/// Reads every plan from the store rather than `TrainingModel.plans`, which holds only the range the
/// week view loaded: removing entries for plans that aren't listed would otherwise remove entries
/// for plans outside that range.
@MainActor
public final class WatchScheduleSync {
    private let model: TrainingModel
    private let scheduler: any PlannedWorkoutScheduling
    private var isSyncing = false

    /// - Parameters:
    ///   - model: Supplies the stores and the athlete's time zone.
    ///   - scheduler: The Watch; `WorkoutKitBridge` in the app, a fake in tests.
    public init(model: TrainingModel, scheduler: any PlannedWorkoutScheduling) {
        self.model = model
        self.scheduler = scheduler
    }

    /// The live sync, or `nil` where WorkoutKit isn't available.
    public static func live(model: TrainingModel) -> WatchScheduleSync? {
        PlannedWorkoutSheetViewModel.liveScheduler.map { WatchScheduleSync(model: model, scheduler: $0) }
    }

    /// Puts the next 7 days of planned workouts on the Watch and removes entries that no longer
    /// belong there (see ``WatchSchedulePlanner``).
    ///
    /// Asks for permission to schedule workouts the first time, and does nothing when it's declined,
    /// the device can't schedule workouts, or the stores can't be read. A plan that fails to schedule
    /// is skipped and tried again on the next run. A call made while a run is in progress returns
    /// at once.
    ///
    /// - Parameter now: The current time, injected so tests can pin the window.
    public func sync(asOf now: Date = .now) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        guard await scheduler.requestAuthorizationIfNeeded() else { return }
        let stores = model.stores
        guard let plans = try? await stores.planStore.plans(in: Date.distantPast...Date.distantFuture),
              let workouts = try? await stores.workoutStore.workouts()
        else { return }

        let workoutsByID = Dictionary(workouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = model.athlete.timeZone
        let scheduler = scheduler
        let result = WatchSchedulePlanner.plan(
            plans, asOf: now, calendar: calendar, cap: scheduler.maxScheduledCount
        ) { plan in
            guard let workout = workoutsByID[plan.workoutID] else { return false }
            return (try? scheduler.validate(workout)) != nil
        }

        // Removals first, so the slots they free are there for the new entries.
        await scheduler.unscheduleAll(except: result.keep)
        for plan in result.toSchedule {
            guard let workout = workoutsByID[plan.workoutID] else { continue }
            try? await scheduler.schedule(plan, workout: workout, calendar: calendar)
        }
    }
}
