import Foundation
import TrainingCore

/// The stretch of a plan-started workout after its last step (MVP2-146): the athlete kept going past
/// the plan, e.g. a run on after the cool-down. The Watch records no step for it, so it would be
/// missing from the step list and look like an unexplained gap at the end of the charts.
///
/// Figures are worked out from the activity as a whole: its distance less the steps', and the heart
/// rate over that time.
public struct ActivityAfterPlan: Equatable, Sendable {
    /// Shorter than this many seconds it isn't worth showing: the Watch ends its last step a few
    /// seconds before it stops the workout.
    public static let minimumSeconds: TimeInterval = 30

    /// The position the stretch is given among the activity's steps: one past the last, so a step
    /// card and a chart span with this number are the same thing (see ``Activity/orderedSteps``).
    public let id: Int
    /// Seconds since the activity began when the last step ended.
    public let start: TimeInterval
    /// Seconds since the activity began when the activity ended.
    public let end: TimeInterval
    /// Distance covered after the last step, in meters: the activity's distance less every step's;
    /// `nil` when either isn't known (a step recorded no distance), or nothing is left.
    public let distanceMeters: Double?
    /// Average heart rate over the stretch, in beats per minute, from the activity's samples; `nil`
    /// without any.
    public let averageHeartRateBPM: Double?

    /// How long the stretch lasts, in seconds.
    public var duration: TimeInterval { end - start }

    /// The stretch after `activity`'s last recorded step, or `nil` when it has no steps or the last one
    /// runs to within ``minimumSeconds`` of the end.
    public static func make(for activity: Activity) -> ActivityAfterPlan? {
        let steps = activity.orderedSteps
        guard let lastEnd = steps.map(\.end).max() else { return nil }
        let start = lastEnd.timeIntervalSince(activity.start)
        let end = activity.duration
        guard end - start >= minimumSeconds else { return nil }

        var distance: Double?
        if let total = activity.distanceMeters {
            var stepsTotal = 0.0
            var allKnown = true
            for step in steps {
                if let meters = step.distanceMeters { stepsTotal += meters } else { allKnown = false }
            }
            if allKnown, total - stepsTotal >= 1 { distance = total - stepsTotal }
        }

        var heartRateSum = 0.0
        var heartRateCount = 0
        for sample in activity.heartRate where sample.bpm.isFinite && sample.bpm > 0 {
            let elapsed = sample.time.timeIntervalSince(activity.start)
            if elapsed >= start, elapsed <= end {
                heartRateSum += sample.bpm
                heartRateCount += 1
            }
        }
        return ActivityAfterPlan(
            id: steps.count, start: start, end: end, distanceMeters: distance,
            averageHeartRateBPM: heartRateCount > 0 ? heartRateSum / Double(heartRateCount) : nil
        )
    }
}
