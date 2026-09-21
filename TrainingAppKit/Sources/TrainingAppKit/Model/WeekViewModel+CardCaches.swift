import Foundation
import TrainingCore

/// Invalidation shared by the card caches (`InputKeyedCache`s for card summaries, linked-plan
/// expectations and intensities).
extension WeekViewModel {
    /// Everything a cached card value can depend on that isn't one of its own inputs: the athlete
    /// (zone settings, pace model) and the intensity thresholds. Changing either drops every card
    /// cache; a change in what is loaded prunes entries whose activity or plan is gone.
    func refreshCardCachesIfNeeded() {
        if cardCacheAthlete != model.athlete || cardCacheIntensityParameters != model.intensityParameters {
            plannedSummaryCache.removeAll()
            linkedExpectationCache.removeAll()
            activityIntensityCache.removeAll()
            planIntensityCache.removeAll()
            cardCacheAthlete = model.athlete
            cardCacheIntensityParameters = model.intensityParameters
        }

        let counts = [model.activities.count, model.plans.count]
        if cardCacheCounts != counts {
            let activityIDs = Set(model.activities.map(\.id))
            let planIDs = Set(model.plans.map(\.id))
            activityIntensityCache.retain(activityIDs)
            plannedSummaryCache.retain(planIDs)
            linkedExpectationCache.retain(planIDs)
            planIntensityCache.retain(planIDs)
            cardCacheCounts = counts
        }
    }

    /// What a plan's cached values depend on: its load override and its workout's steps.
    func cardInputs(for plan: PlannedActivity, workout: StructuredWorkout?) -> [Int] {
        [plan.expectedLoadOverride?.hashValue ?? 0, workout?.hashValue ?? 0]
    }
}
