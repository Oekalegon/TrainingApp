import Foundation
import TrainingCore

/// Forecasting planned workouts from the athlete's own paces (MVP2-35, MVP2-111).
extension WeekViewModel {
    /// How far back ``paceHistory`` looks. Long enough to have run most kinds of workout before,
    /// short enough that the paces are about the athlete's current fitness; the estimator weighs
    /// recent activities more on top of this.
    static let paceHistoryDays = 180

    /// What a ``paceHistory`` was built from: rebuilt when an activity is added or removed, a plan
    /// is linked or unlinked, the library changes, the athlete's zones change or a day passes.
    struct PaceHistoryKey: Equatable {
        let activityCount: Int
        let linkedPlanIDs: Set<UUID>
        let workoutCount: Int
        let athlete: AthleteProfile
        let day: Date
    }

    /// Re-reads the last ``paceHistoryDays`` days of activities from the store into ``paceHistory``
    /// when anything it depends on changed. Called from ``refreshWeekCachesIfNeeded()``, so it runs
    /// after every load, import and link change. A failed read keeps the previous history.
    ///
    /// - Parameter today: The end of the range read.
    func refreshPaceHistoryIfNeeded(asOf today: Date = .now) async {
        let key = PaceHistoryKey(
            activityCount: model.activities.count,
            linkedPlanIDs: Set(model.plans.filter { $0.completedActivityID != nil }.map(\.id)),
            workoutCount: model.workouts.count,
            athlete: model.athlete,
            day: athleteCalendar.startOfDay(for: today)
        )
        guard key != paceHistoryKey else { return }
        paceHistoryKey = key

        let start = athleteCalendar.date(byAdding: .day, value: -Self.paceHistoryDays, to: today) ?? today
        let range = start...today
        let stores = model.stores
        guard let activities = try? await stores.activityStore.activities(in: range),
              let plans = try? await stores.planStore.plans(in: range)
        else {
            // Retry on the next refresh, unless a newer one has already taken over.
            if paceHistoryKey == key { paceHistoryKey = nil }
            return
        }
        let workouts = model.workouts
        let athlete = model.athlete
        let gapThresholdSeconds = statisticsCalculator.gapThresholdSeconds
        let history = await Task.detached(priority: .utility) {
            PaceHistory(
                activities: activities, plans: plans, workouts: workouts,
                athlete: athlete, gapThresholdSeconds: gapThresholdSeconds
            )
        }.value
        // A newer refresh started while this one was reading: let that one's result stand.
        guard paceHistoryKey == key else { return }
        paceHistory = history
        paceHistoryGeneration += 1
    }

    /// The estimator the cards and the detail sheet forecast with — falling back to the same
    /// duration rules as the week's statistics when there's no history.
    var paceEstimator: HistoricalPaceEstimator {
        HistoricalPaceEstimator(durationEstimator: statisticsCalculator.durationEstimator)
    }

    /// What a plan's projected values depend on: ``cardInputs(for:workout:)`` plus the pace history.
    func projectionInputs(for plan: PlannedActivity, workout: StructuredWorkout?) -> [Int] {
        cardInputs(for: plan, workout: workout) + [plan.date.hashValue, paceHistoryGeneration]
    }
}
