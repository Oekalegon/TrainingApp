import Foundation
import TrainingCore

/// A planned workout's expected load, refined with what the athlete's completed plans actually scored
/// (TrainingKit's `LinkedActivityRefinedEstimator`, shipped in TrainingKit#100 and exposed by #101).
///
/// TrainingKit already refines the load series (the projected form and fatigue) and the calendar export.
/// The week view's cards, the stats bar, the daily-load split, the planned-workout sheets and the library
/// compute their own planned loads, so without this they would show the base estimator's figure beside a
/// refined one.
extension WeekViewModel {
    /// What the refined estimator depends on that the week view can see without reading the store:
    /// the athlete (the zones that score each completed run) and the library's workouts (the
    /// references hold copies of them, so an edit that keeps the count must count too). Changes to the
    /// activities and plans themselves arrive through
    /// `refreshWeekCachesIfNeeded(asOf:activitiesChanged:)`, which forces a refresh.
    struct PlannedLoadKey: Equatable {
        let athlete: AthleteProfile
        let workouts: Int
    }

    /// Rebuilds the refined planned-load estimator (`TrainingModel.loadRefinedEstimator()`) when its key
    /// changed or `force` is set, and replaces ``statisticsCalculator`` with one that uses it.
    ///
    /// ``plannedLoadGeneration`` (and with it every cached planned load) only moves when the
    /// references actually changed, so a refresh that read the same completed plans costs the read but
    /// no recomputation. The model reads the whole plan history and scores every completed activity on
    /// each call, which is why this runs after imports, links and library or athlete changes, not on
    /// every week swipe, and why it runs last in ``refreshWeekCachesIfNeeded(asOf:activitiesChanged:)``:
    /// the graphs and the pace history don't wait for it.
    ///
    /// Overlapping refreshes (a pull-to-refresh during a link, say) each take a token, and only the
    /// newest applies its result, so a slow, older read can't replace a newer one.
    ///
    /// The model keeps the estimator it built until the next `recompute`, so right after an import,
    /// link or other change that went through it this costs nothing: `recompute` just built it
    /// (MVP2-160). It uses the throwing variant: when a store can't be read, the previous estimator is
    /// kept and the next refresh tries again, so the cards don't flip back to unrefined figures on a
    /// transient error. A base estimator that does arrive (every completed plan was deleted) is a real
    /// change and applies.
    ///
    /// - Parameter force: Rebuild even if the key is unchanged.
    func refreshPlannedLoadIfNeeded(force: Bool = false) async {
        var hasher = Hasher()
        for workout in model.workouts { hasher.combine(workout) }
        let key = PlannedLoadKey(athlete: model.athlete, workouts: hasher.finalize())
        guard force || key != plannedLoadKey else { return }
        plannedLoadKey = key
        plannedLoadRefreshToken += 1
        let token = plannedLoadRefreshToken

        let estimator: any PlannedLoadEstimator
        do {
            estimator = try await model.loadRefinedEstimator()
        } catch {
            // Keep what the cards show and try again on the next refresh, unless a newer one has taken over.
            if token == plannedLoadRefreshToken { plannedLoadKey = nil }
            return
        }
        guard token == plannedLoadRefreshToken else { return }
        let refined = estimator as? LinkedActivityRefinedEstimator
        guard refined?.references != plannedLoadReferences else { return }
        plannedLoadReferences = refined?.references
        refinedLoadEstimator = refined
        statisticsCalculator = StatisticsCalculator(estimator: estimator)
        plannedLoadGeneration += 1
    }

    /// A calculator whose planned loads are those the athlete could have expected before `date`: the
    /// refinement without the completed plans done on or after it. A completed plan's own activity is
    /// among the references, so estimating the plan with it would compare the activity with itself;
    /// the linked activity's card ("85 / ~90") uses this to keep its expectation honest. The same
    /// calculator as ``statisticsCalculator`` while nothing refines the estimate.
    ///
    /// - Parameter date: References dated on or after this instant are left out.
    func plannedLoadCalculator(before date: Date) -> StatisticsCalculator {
        guard let refined = refinedLoadEstimator else { return statisticsCalculator }
        return StatisticsCalculator(estimator: refined.excludingReferences(onOrAfter: date))
    }
}
