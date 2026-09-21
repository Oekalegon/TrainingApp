import Foundation
import TrainingCore

extension WeekViewModel {
    /// What the plan a completed activity is linked to expected, for the planned values its card
    /// shows next to and under the actual ones.
    public struct LinkedPlanExpectation: Equatable, Sendable {
        /// Expected TRIMP: the plan's override, else the estimator's figure.
        public let load: Double?
        /// Expected duration — exact for a duration-based workout, projected from the athlete's pace
        /// model for a distance-based one.
        public let duration: TimeInterval?
        /// Expected distance — exact for a distance-based workout, projected from the athlete's pace
        /// model for a duration-based one; `nil` when the projection can't be made (no heart-rate zone
        /// settings recorded).
        public let distanceMeters: Double?
    }

    /// What the plan `activity` is linked to expected, or `nil` when it has no linked plan among the
    /// loaded ones or that plan's workout is gone.
    ///
    /// Both duration and distance, unlike ``plannedCardSummary(for:)``, which shows only the one a
    /// workout is defined by: on an activity's card the planned values sit under the actual ones, so
    /// each actual value needs its counterpart. Cached per plan against its load override and its
    /// workout's steps, and dropped when the athlete's zones or pace model change — the projected
    /// distance and duration depend on both.
    public func linkedPlanExpectation(for activity: Activity) -> LinkedPlanExpectation? {
        guard let planID = activity.linkedPlanID,
              let plan = model.plans.first(where: { $0.id == planID }),
              let workout = model.workouts.first(where: { $0.id == plan.workoutID })
        else { return nil }

        refreshCardCachesIfNeeded()
        return linkedExpectationCache.value(for: plan.id, inputs: cardInputs(for: plan, workout: workout)) {
            let projection = statisticsCalculator.projection(for: workout, athlete: model.athlete)
            return LinkedPlanExpectation(
                load: plannedCardSummary(for: plan).load,
                duration: projection.duration,
                distanceMeters: projection.distanceMeters
            )
        }
    }
}
