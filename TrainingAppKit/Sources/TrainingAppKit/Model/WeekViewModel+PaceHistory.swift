import Foundation
import TrainingCore

/// Forecasting planned workouts from the athlete's own paces (MVP2-35, MVP2-111).
extension WeekViewModel {
    /// How far back ``paceHistory`` looks. Long enough to have run most kinds of workout before,
    /// short enough that the paces are about the athlete's current fitness; the forecast weighs
    /// recent activities more on top of this.
    static let paceHistoryDays = 180

    /// The last ``paceHistoryDays`` days of completed activities (TrainingKit's
    /// `TrainingModel.paceHistory`), which the planned cards, the linked activities' planned values,
    /// the detail sheet and the week's planned totals are all forecast from. Empty until
    /// ``refreshPaceHistoryIfNeeded(asOf:)`` has read the store.
    public var paceHistory: PaceHistory { model.paceHistory }

    /// What ``paceHistory`` was built from: rebuilt when an activity is added or removed, a plan
    /// is linked or unlinked, the library changes, the athlete's zones change or a day passes.
    struct PaceHistoryKey: Equatable {
        let activityCount: Int
        let linkedPlanIDs: Set<UUID>
        let workoutCount: Int
        let athlete: AthleteProfile
        let day: Date
    }

    /// Has the model re-read the last ``paceHistoryDays`` days of activities into ``paceHistory``
    /// when anything it depends on changed. Called from ``refreshWeekCachesIfNeeded()``, so it runs
    /// after every load, import and link change. A failed read keeps the previous history and is
    /// retried on the next call.
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
        do {
            try await model.refreshPaceHistory(
                in: start...today, gapThresholdSeconds: statisticsCalculator.gapThresholdSeconds
            )
            paceHistoryGeneration += 1
        } catch {
            // Retry on the next refresh, unless a newer one has already taken over.
            if paceHistoryKey == key { paceHistoryKey = nil }
        }
    }

    /// What a plan's projected values depend on: ``cardInputs(for:workout:)`` plus the plan's date
    /// (the forecast's cutoff) and the pace history.
    func projectionInputs(for plan: PlannedActivity, workout: StructuredWorkout?) -> [Int] {
        cardInputs(for: plan, workout: workout) + [plan.date.hashValue, paceHistoryGeneration]
    }
}
