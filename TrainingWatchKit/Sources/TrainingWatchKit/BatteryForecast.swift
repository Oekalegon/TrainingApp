import SwiftUI

/// Predicts how the watch's battery will be at the end of a planned workout (WATCH-119): the drain
/// per hour from the readings so far, blended with a typical rate while there is little to measure
/// from, and from that the charge after the rest of the workout and a verdict on it. Pure logic, so
/// it can be tested without a run; the watch app collects the readings.
public struct BatteryForecast: Sendable, Hashable {
    /// One battery reading during the run.
    public struct Reading: Sendable, Hashable {
        /// The workout time it was taken at, in seconds.
        public let time: TimeInterval
        /// The charge, 0 to 1.
        public let level: Double

        public init(time: TimeInterval, level: Double) {
            self.time = time
            self.level = level
        }
    }

    /// Whether the charge at the end of the workout is enough.
    public enum Verdict: Sendable, Hashable {
        /// At least 20% left at the end.
        case enough
        /// 10% up to 20% left.
        case tight
        /// Under 10% left, but not empty.
        case critical
        /// It will run out before the workout ends.
        case runsOut
    }

    /// A typical drain of an outdoor run with GPS and heart rate, as a share of the full charge per
    /// hour, used until the run has shown the real one. A guess, to tune from real runs.
    public static let typicalDrainPerHour = 0.12
    /// How far back the readings count, in seconds.
    public static let window: TimeInterval = 20 * 60
    /// How long a run has to be measured for before the measured drain counts fully, in seconds.
    public static let fullTrustAfter: TimeInterval = 15 * 60
    /// The share of the charge kept as a margin when judging the end of the workout, because the
    /// drain is not steady.
    public static let safetyMargin = 0.03

    /// The drain per hour the forecast uses, as a share of the full charge.
    public let drainPerHour: Double

    /// - Parameters:
    ///   - readings: The battery readings of the run so far, oldest first.
    ///   - prior: The drain per hour to use where the run has not shown one yet.
    public init(readings: [Reading], prior: Double = typicalDrainPerHour) {
        let recent = Self.recent(readings)
        guard let first = recent.first, let last = recent.last, last.time > first.time else {
            drainPerHour = prior
            return
        }
        let span = last.time - first.time
        let drop = first.level - last.level
        // The level moves in coarse steps, so a short stretch says little: a measurement needs a few
        // minutes and a real drop, or a longer time (when no drop at all is also an answer).
        let measurable = (span >= 5 * 60 && drop >= 0.02) || span >= Self.fullTrustAfter
        guard measurable, drop >= 0 else {
            drainPerHour = prior
            return
        }
        let measured = max(drop, 0.005) / span * 3600
        let weight = min(span / Self.fullTrustAfter, 1)
        drainPerHour = prior * (1 - weight) + measured * weight
    }

    private static func recent(_ readings: [Reading]) -> [Reading] {
        guard let last = readings.last else { return [] }
        return readings.filter { last.time - $0.time <= window }
    }

    /// The charge after `seconds` more of the workout, which is below 0 when it would run out.
    ///
    /// - Parameters:
    ///   - seconds: How much of the workout is left.
    ///   - level: The charge now, 0 to 1.
    public func level(after seconds: TimeInterval, from level: Double) -> Double {
        level - drainPerHour * max(seconds, 0) / 3600
    }

    /// How long the charge lasts at this drain, in seconds.
    ///
    /// - Parameter level: The charge now, 0 to 1.
    public func timeUntilEmpty(from level: Double) -> TimeInterval {
        drainPerHour > 0 ? max(level, 0) / drainPerHour * 3600 : .infinity
    }

    /// How the charge at the end of the workout rates: with the safety margin taken off, enough from
    /// 20%, tight from 10%, critical above 0 and otherwise it runs out.
    ///
    /// - Parameter endLevel: ``level(after:from:)``.
    public func verdict(endLevel: Double) -> Verdict {
        let margined = endLevel - Self.safetyMargin
        if margined >= 0.20 { return .enough }
        if margined >= 0.10 { return .tight }
        if margined >= 0 { return .critical }
        return .runsOut
    }
}

extension BatteryForecast.Verdict {
    /// Green, yellow, orange or red.
    public var color: Color {
        switch self {
        case .enough: .green
        case .tight: .yellow
        case .critical: .orange
        case .runsOut: .red
        }
    }
}

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
