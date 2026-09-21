import Foundation
import TrainingCore

/// Linking a completed activity to the planned workout it fulfilled (MVP2-42). The matching itself
/// is automatic (``TrainingModel``'s import runs ``PlanReconciler``); this is the athlete's way to
/// confirm, correct or undo it.
extension WeekViewModel {
    /// The plan link `activity`'s detail sheet shows, or `nil` when there's nothing to show: the
    /// activity isn't linked and no unmatched plan exists on its day.
    public func planLinkContext(for activity: Activity) -> PlanLinkContext? {
        let linked = activity.linkedPlanID.flatMap { id in model.plans.first { $0.id == id } }
        let candidates = plans(on: activity.start)
            .filter { $0.completedActivityID == nil && $0.id != linked?.id }
            .map(planOption)
        guard linked != nil || !candidates.isEmpty else { return nil }
        return PlanLinkContext(
            linkedPlan: linked.map(planOption),
            isAmbiguous: model.planMatchAmbiguities.contains { $0.activityID == activity.id },
            candidates: candidates
        )
    }

    /// Links `activity` to the plan `planID` (replacing its current link), or confirms the current
    /// one when they're the same.
    ///
    /// - Returns: `true` if the link was made. `false` (nothing changed) if the plan isn't on the
    ///   activity's day or a store failed — the sheet stays open with a message, like a refused join.
    @discardableResult
    public func linkActivity(_ activity: Activity, toPlan planID: UUID, asOf today: Date = .now) async -> Bool {
        do {
            try await model.linkActivity(id: activity.id, toPlan: planID, asOf: today)
        } catch {
            return false
        }
        await refreshWeekCachesIfNeeded()
        return true
    }

    /// Removes `activity`'s link to its plan. It isn't matched again automatically afterwards.
    ///
    /// - Returns: `true` if the link was removed.
    @discardableResult
    public func unlinkActivity(_ activity: Activity, asOf today: Date = .now) async -> Bool {
        do {
            try await model.unlinkActivity(id: activity.id, asOf: today)
        } catch {
            return false
        }
        await refreshWeekCachesIfNeeded()
        return true
    }

    private func planOption(_ plan: PlannedActivity) -> PlanLinkContext.PlanOption {
        let summary = plannedCardSummary(for: plan)
        return PlanLinkContext.PlanOption(
            id: plan.id, title: summary.name ?? summary.sport.displayName, extent: summary.extent
        )
    }
}
