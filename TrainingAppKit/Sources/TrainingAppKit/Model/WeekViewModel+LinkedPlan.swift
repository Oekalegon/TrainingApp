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
        /// Whether ``load`` is the estimator's figure rather than the plan's override (MVP2-8).
        public let isLoadEstimated: Bool
        /// Whether ``duration`` is forecast rather than the sum of the workout's time steps (MVP2-8).
        public let isDurationEstimated: Bool
        /// Whether ``distanceMeters`` is forecast rather than the sum of the workout's distance
        /// steps (MVP2-8).
        public let isDistanceEstimated: Bool
    }

    /// What the plan `activity` is linked to expected, or `nil` when it has no linked plan among the
    /// loaded ones or that plan's workout is gone.
    ///
    /// Both duration and distance, like ``plannedCardSummary(for:)``: on an activity's card the
    /// planned values sit under the actual ones, so each actual value needs its counterpart. Unlike
    /// that summary, the forecast uses only activities from before this one, so the plan's expectation isn't informed by how the athlete actually ran it. Cached per
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
            // Estimated as it was before this activity: its own load is among the refinement's
            // references, and a plan's expectation mustn't be informed by how it was actually done.
            let calculator = plannedLoadCalculator(before: activity.start)
            let projection = calculator.projection(
                for: workout, athlete: model.athlete, paceHistory: paceHistory,
                before: activity.start, excluding: activity.id
            )
            let summary = PlannedCardSummary.make(
                plan: plan, workout: workout, athlete: model.athlete, calculator: calculator, history: paceHistory
            )
            return LinkedPlanExpectation(
                load: summary.load,
                duration: projection.duration,
                distanceMeters: projection.distanceMeters,
                isLoadEstimated: summary.isLoadEstimated,
                isDurationEstimated: workout.isDurationForecast,
                isDistanceEstimated: workout.isDistanceForecast
            )
        }
    }

    /// The title every surface shows for a completed `activity` (MVP2-152): the name of the workout
    /// of the plan it completed (e.g. "10 km Long Run"), else the sport's name — for an activity with
    /// no plan, one whose workout is gone, or a workout with an empty name. The card, the detail
    /// sheet, the overlap review and the join text all take it from here so they can't disagree.
    public func activityTitle(for activity: Activity) -> String {
        if let planID = activity.linkedPlanID,
           let plan = model.plans.first(where: { $0.id == planID }),
           let name = workout(for: plan)?.name, !name.isEmpty {
            return name
        }
        return activity.sport.displayName
    }
}
