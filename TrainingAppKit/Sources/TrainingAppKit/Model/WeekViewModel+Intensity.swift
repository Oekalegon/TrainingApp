import Foundation
import TrainingCore

/// The intensity (MVP2-43) shown on the day list's activity and planned-workout cards.
extension WeekViewModel {
    /// The intensity of a completed activity, checked against its linked plan when there is one —
    /// see `TrainingModel.intensity(of:)`. `nil` when there is nothing to classify it from.
    ///
    /// Cached per activity (see ``activityIntensityCache``): the day list re-renders on every
    /// touch-move frame of the week-swipe drag, and classifying walks the activity's heart-rate
    /// samples. An entry is reused only while the activity's link, heart-rate data, duration and
    /// linked workout are unchanged, and the whole cache is dropped when the athlete or the
    /// classifier thresholds change.
    public func intensity(for activity: Activity) -> IntensityAssessment? {
        refreshCardCachesIfNeeded()
        let plan = model.plans.first { $0.id == activity.linkedPlanID }
        let workout = plan.flatMap { plan in model.workouts.first { $0.id == plan.workoutID } }
        let inputs = [
            activity.linkedPlanID?.hashValue ?? 0,
            activity.heartRate.count,
            activity.duration.hashValue,
            workout?.hashValue ?? 0,
        ]
        return activityIntensityCache.value(for: activity.id, inputs: inputs) {
            model.intensity(of: activity)
        }
    }

    /// The intended intensity of a planned workout — see `TrainingModel.intensity(of:)`. `nil` when
    /// its workout isn't loaded. Cached like ``intensity(for:)-(Activity)``.
    public func intensity(for plan: PlannedActivity) -> IntensityAssessment? {
        refreshCardCachesIfNeeded()
        let workout = workout(for: plan)
        return planIntensityCache.value(for: plan.id, inputs: cardInputs(for: plan, workout: workout)) {
            model.intensity(of: plan)
        }
    }
}
