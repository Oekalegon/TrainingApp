import Foundation
import TrainingCore

extension WeekViewModel {
    /// What the plan a completed activity is linked to expected, for the planned values its card
    /// shows next to and under the actual ones.
    public struct LinkedPlanExpectation: Equatable, Sendable {
        /// Expected TRIMP: the plan's override, else the estimator's figure.
        public let load: Double?
        /// Expected duration — exact for a duration-based workout, forecast from the athlete's
        /// earlier paces for distance and open steps (see ``WeekViewModel/paceHistory``).
        public let duration: TimeInterval?
        /// Expected distance — exact for a distance-based workout, forecast from the athlete's
        /// earlier paces for time and open steps; `nil` when the forecast can't be made (no heart-rate
        /// zone settings recorded).
        public let distanceMeters: Double?
    }

    /// What the plan `activity` is linked to expected, or `nil` when it has no linked plan among the
    /// loaded ones or that plan's workout is gone.
    ///
    /// Both duration and distance, unlike ``plannedCardSummary(for:)``, which shows only the one a
    /// workout is defined by: on an activity's card the planned values sit under the actual ones, so
    /// each actual value needs its counterpart. The forecast uses only activities from before this
    /// one, so the plan's expectation isn't informed by how the athlete actually ran it. Cached per
    /// plan against its load override, its workout's steps and the pace history, and dropped when
    /// the athlete's zones or pace model change — the forecast depends on all of them.
    public func linkedPlanExpectation(for activity: Activity) -> LinkedPlanExpectation? {
        guard let planID = activity.linkedPlanID,
              let plan = model.plans.first(where: { $0.id == planID }),
              let workout = model.workouts.first(where: { $0.id == plan.workoutID })
        else { return nil }

        refreshCardCachesIfNeeded()
        let inputs = projectionInputs(for: plan, workout: workout) + [activity.id.hashValue, activity.start.hashValue]
        return linkedExpectationCache.value(for: plan.id, inputs: inputs) {
            let projection = statisticsCalculator.projection(
                for: workout, athlete: model.athlete, paceHistory: paceHistory,
                before: activity.start, excluding: activity.id
            )
            return LinkedPlanExpectation(
                load: plannedCardSummary(for: plan).load,
                duration: projection.duration,
                distanceMeters: projection.distanceMeters
            )
        }
    }
}
