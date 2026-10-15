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
    /// ``refreshPaceHistoryIfNeeded(asOf:force:)`` has read the store.
    public var paceHistory: PaceHistory { model.paceHistory }

    /// What ``paceHistory`` depends on that the week view can see without reading the store: the
    /// athlete (zones, pace model), the library (linked activities' steps) and the day (the range's
    /// end). Deliberately nothing about the loaded weeks: those change on every week swipe while
    /// the 180-day history doesn't. Changes to the stored activities themselves arrive through
    /// `refreshWeekCachesIfNeeded(asOf:activitiesChanged:)` instead.
    struct PaceHistoryKey: Equatable {
        let athlete: AthleteProfile
        let workoutCount: Int
        let day: Date
    }

    /// Has the model re-read the last ``paceHistoryDays`` days of activities into ``paceHistory``
    /// when the key changed or `force` is set. Called from ``refreshWeekCachesIfNeeded(asOf:activitiesChanged:)``,
    /// which forces it after an import, resync, dedup, link, join or delete.
    ///
    /// ``paceHistoryGeneration`` (and with it every cached card and stats page that forecasts from
    /// the history) only moves when the history actually changed, so a refresh that read the same
    /// activities costs the read but no recomputation. A failed read keeps the previous history and
    /// is retried on the next call.
    ///
    /// - Parameters:
    ///   - today: The end of the range read.
    ///   - force: Re-read even if the key is unchanged.
    func refreshPaceHistoryIfNeeded(asOf today: Date = .now, force: Bool = false) async {
        let key = PaceHistoryKey(
            athlete: model.athlete, workoutCount: model.workouts.count, day: athleteCalendar.startOfDay(for: today)
        )
        guard force || key != paceHistoryKey else { return }
        paceHistoryKey = key

        let start = athleteCalendar.date(byAdding: .day, value: -Self.paceHistoryDays, to: today) ?? today
        let previous = model.paceHistory
        do {
            try await model.refreshPaceHistory(
                in: start...today, gapThresholdSeconds: statisticsCalculator.gapThresholdSeconds
            )
        } catch {
            // Retry on the next refresh, unless a newer one has already taken over.
            if paceHistoryKey == key { paceHistoryKey = nil }
            return
        }
        if model.paceHistory != previous {
            paceHistoryGeneration += 1
        }
    }

    /// What a plan's projected values depend on: ``cardInputs(for:workout:)`` plus the plan's date
    /// (the forecast's cutoff) and the pace history.
    func projectionInputs(for plan: PlannedActivity, workout: StructuredWorkout?) -> [Int] {
        cardInputs(for: plan, workout: workout) + [plan.date.hashValue, paceHistoryGeneration]
    }
}
