import Foundation

/// How much of a planned workout is left, for the battery forecast.
public struct RemainingEstimate: Sendable, Hashable {
    /// The time left, in seconds, of what could be estimated.
    public let seconds: TimeInterval
    /// Whether every step has been counted: an open step has no end, so then the estimate is short.
    public let isComplete: Bool
}

extension WorkoutStepEngine {
    /// How much of the workout is left: what is left of the current step and all the steps after it.
    /// A time goal counts as it is, a distance goal at the given pace, and an open step can't be
    /// counted, which makes the estimate incomplete.
    ///
    /// - Parameters:
    ///   - progress: How far into the current step the run is.
    ///   - secondsPerMeter: The pace to count distances at.
    /// - Returns: `nil` once the workout is over.
    public func remaining(progress: StepProgress?, secondsPerMeter: Double) -> RemainingEstimate? {
        guard let current else { return nil }
        var seconds = 0.0
        var complete = true
        if let time = progress?.remainingTime {
            seconds += time
        } else if let distance = progress?.remainingDistance {
            seconds += distance * secondsPerMeter
        } else {
            complete = false
        }
        for step in steps where step.index > current.index {
            switch step.step.goal {
            case .time(let time): seconds += time
            case .distance(let meters): seconds += meters * secondsPerMeter
            case .open: complete = false
            }
        }
        return RemainingEstimate(seconds: seconds, isComplete: complete)
    }
}
