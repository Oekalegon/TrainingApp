import Foundation
import TrainingCore

extension MicroCycleViewModel {
    /// The view model for the Plans screen (MVP5-125). Whatever it changes about which plan is active
    /// reaches this view model through ``activePlanChanged(asOf:)``.
    public func plansViewModel() -> PlansViewModel {
        let viewModel = PlansViewModel(model: model, estimator: { [weak self] in
            _ = self?.plannedLoadGeneration
            return self?.statisticsCalculator.estimator ?? TRIMPPlanEstimator()
        })
        viewModel.onPlansChanged = { [weak self] in await self?.activePlanChanged() }
        return viewModel
    }

    /// The view model for the Create Plan wizard (MVP5-146), which stores a draft plan from the Plans tab's New Plan action.
    public func createPlanViewModel() -> CreatePlanViewModel {
        CreatePlanViewModel(model: model)
    }

    /// Catches up with a change of the active plan, or of its workouts, made outside this view model
    /// (MVP5-125): `TrainingModel` has already swapped `plans` and `cycles` for the new active plan's,
    /// so what is left is what this view model keeps beside them. Drops the cycles peeked from the
    /// previous plan, re-resolves the displayed period from the new plan's micro-cycles, refreshes the
    /// caches, and has the Watch schedule follow.
    ///
    /// - Parameter today: Passed through to the cache refresh and the Watch sync.
    public func activePlanChanged(asOf today: Date = .now) async {
        peekedCycles = []
        await peekCycles()
        refreshDisplayedPeriod()
        await refreshPeriodCachesIfNeeded(asOf: today, activitiesChanged: true)
        requestWatchSync(asOf: today)
    }
}
