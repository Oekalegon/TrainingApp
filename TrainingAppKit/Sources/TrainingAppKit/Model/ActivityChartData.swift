import Foundation
import TrainingCore

/// What the activity detail's heart-rate and pace charts draw (MVP2-146): the two series against time
/// since the activity began, and the steps the Watch recorded as spans of that same time, so each
/// step's start shows as a marker aligned with the plan's steps.
///
/// Built once when the sheet opens (the activity doesn't change underneath it): heart rate is averaged
/// into at most ``maximumPoints`` points and speed is smoothed and turned into pace, so the chart
/// renders a few hundred marks however long the activity was.
public struct ActivityChartData: Equatable, Sendable {
    /// One reading on a chart.
    public struct Point: Equatable, Sendable {
        /// Seconds since the activity began.
        public let elapsed: TimeInterval
        /// Beats per minute for heart rate; seconds per kilometer for pace.
        public let value: Double
        /// Which unbroken stretch the point belongs to: a pause, or a stop for pace, starts a new one,
        /// so the chart draws a gap there instead of a line across it.
        public let segment: Int
    }

    /// A recorded step as a stretch of the time axis.
    public struct StepSpan: Identifiable, Equatable, Sendable {
        /// The step's position among the recorded steps, from 0.
        public let id: Int
        /// The role the plan gives the step, when the steps could be laid over the plan; `nil` when
        /// they could not, or for a step the plan doesn't have.
        public let kind: StepKind?
        /// Seconds since the activity began when the step started.
        public let start: TimeInterval
        /// Seconds since the activity began when the step ended.
        public let end: TimeInterval
    }

    /// The most points either series is reduced to.
    public static let maximumPoints = 400
    /// Speed below this (meters a second, about 33 min/km) is a stop, not a pace.
    static let minimumMovingSpeed = 0.5
    /// A silence this long, in seconds, starts a new segment.
    static let gapSeconds: TimeInterval = 30
    /// How many speed samples (5 s each) the pace is averaged over, centred: 35 s.
    static let paceSmoothingSamples = 7

    /// Heart rate in beats per minute against time; empty without samples.
    public let heartRate: [Point]
    /// Pace in seconds per kilometer against time; empty without speed samples.
    public let pace: [Point]
    /// The recorded steps in order; empty for an activity with none.
    public let steps: [StepSpan]
    /// The activity's duration in seconds: the charts' time axis runs from 0 to this.
    public let duration: TimeInterval
    /// The range the pace axis covers, in seconds per kilometer (the larger number is the slower
    /// pace): the middle 90% of the pace readings, padded, so a stop or a walk doesn't squash the
    /// running. `nil` without pace.
    public let paceDomain: ClosedRange<Double>?

    /// Whether the heart-rate chart has anything to draw.
    public var hasHeartRate: Bool { heartRate.count > 1 }
    /// Whether the pace chart has anything to draw.
    public var hasPace: Bool { pace.count > 1 }

    /// Axis values for `range`: multiples of the smallest of `steps` that gives no more than
    /// `maximumCount` of them, so ticks fall on round numbers (every 10 minutes, every 30 seconds per
    /// kilometer) rather than at whatever the range's ends happen to divide into.
    ///
    /// - Parameters:
    ///   - range: The values the axis covers.
    ///   - steps: The step sizes to choose from, smallest first.
    ///   - maximumCount: The most values to return.
    /// - Returns: The ticks in increasing order; empty for an empty range.
    static func niceTicks(in range: ClosedRange<Double>, steps: [Double], maximumCount: Int = 6) -> [Double] {
        guard range.upperBound > range.lowerBound, let fallback = steps.last else { return [] }
        let step = steps.first { (range.upperBound - range.lowerBound) / $0 <= Double(maximumCount) } ?? fallback
        var ticks: [Double] = []
        var value = (range.lowerBound / step).rounded(.up) * step
        while value <= range.upperBound + step * 1e-9 {
            ticks.append(value)
            value += step
        }
        return ticks
    }

    /// Step sizes for a time axis, in seconds.
    static let timeTickSteps: [Double] = [30, 60, 120, 300, 600, 900, 1200, 1800, 3600, 7200]
    /// Step sizes for a pace axis, in seconds per kilometer.
    static let paceTickSteps: [Double] = [10, 15, 30, 60, 120, 300]

    /// The chart data for `activity`.
    ///
    /// - Parameters:
    ///   - activity: The activity; its heart-rate, speed and recorded steps are read.
    ///   - workout: The workout of the plan the activity completed, to say what each recorded step was
    ///     (warm-up, work...); `nil` leaves the steps without a role.
    public static func make(for activity: Activity, workout: StructuredWorkout?) -> ActivityChartData {
        let duration = max(activity.duration, 0)
        let heartRate = heartRatePoints(activity.heartRate, start: activity.start, duration: duration)
        let (pace, domain) = pacePoints(activity.speed, start: activity.start, duration: duration)
        return ActivityChartData(
            heartRate: heartRate, pace: pace, steps: stepSpans(of: activity, workout: workout, duration: duration),
            duration: duration, paceDomain: domain
        )
    }

    /// Heart rate averaged into buckets of `duration / maximumPoints` seconds (at least a second), a
    /// new segment after any silence of ``gapSeconds``.
    private static func heartRatePoints(_ samples: [HeartRateSample], start: Date, duration: TimeInterval) -> [Point] {
        let sorted = samples
            .map { (elapsed: $0.time.timeIntervalSince(start), bpm: $0.bpm) }
            .filter { $0.elapsed >= 0 && $0.elapsed <= duration && $0.bpm.isFinite && $0.bpm > 0 }
            .sorted { $0.elapsed < $1.elapsed }
        guard !sorted.isEmpty else { return [] }
        let bucket = max(duration / Double(maximumPoints), 1)
        var points: [Point] = []
        var segment = 0
        var current = (index: 0, elapsed: 0.0, bpm: 0.0, count: 0)
        var lastElapsed = sorted[0].elapsed

        func flush() {
            guard current.count > 0 else { return }
            points.append(Point(
                elapsed: current.elapsed / Double(current.count), value: current.bpm / Double(current.count), segment: segment
            ))
            current = (current.index, 0, 0, 0)
        }
        for sample in sorted {
            if sample.elapsed - lastElapsed > gapSeconds {
                flush()
                segment += 1
            }
            lastElapsed = sample.elapsed
            let index = Int(sample.elapsed / bucket)
            if index != current.index {
                flush()
                current.index = index
            }
            current.elapsed += sample.elapsed
            current.bpm += sample.bpm
            current.count += 1
        }
        flush()
        return points
    }

    /// Pace from speed, smoothed over ``paceSmoothingSamples`` samples; a stop (below
    /// ``minimumMovingSpeed``) or a silence of ``gapSeconds`` starts a new segment.
    private static func pacePoints(
        _ samples: [SpeedSample], start: Date, duration: TimeInterval
    ) -> ([Point], ClosedRange<Double>?) {
        let sorted = samples
            .map { (elapsed: $0.time.timeIntervalSince(start), speed: $0.metersPerSecond) }
            .filter { $0.elapsed >= 0 && $0.elapsed <= duration && $0.speed.isFinite && $0.speed >= 0 }
            .sorted { $0.elapsed < $1.elapsed }
        guard !sorted.isEmpty else { return ([], nil) }

        let half = paceSmoothingSamples / 2
        var points: [Point] = []
        var segment = 0
        var broken = false
        var previous = sorted[0].elapsed
        for (index, sample) in sorted.enumerated() {
            if sample.elapsed - previous > gapSeconds { broken = true }
            previous = sample.elapsed
            // Averaged over the neighbours that are close in time, so a stop doesn't drag in the run
            // either side of it.
            let window = sorted[max(0, index - half)...min(sorted.count - 1, index + half)]
                .filter { abs($0.elapsed - sample.elapsed) <= Double(half) * 5 + 1 }
            let mean = window.map(\.speed).reduce(0, +) / Double(window.count)
            guard mean >= minimumMovingSpeed else {
                broken = true
                continue
            }
            if broken {
                if !points.isEmpty { segment += 1 }
                broken = false
            }
            points.append(Point(elapsed: sample.elapsed, value: 1000 / mean, segment: segment))
        }
        guard points.count > 1 else { return (points, nil) }

        let values = points.map(\.value).sorted()
        let low = values[Int(Double(values.count - 1) * 0.05)]
        let high = values[Int(Double(values.count - 1) * 0.95)]
        let pad = max((high - low) * 0.1, 10)
        let domain = (low - pad)...(high + pad)
        // Values beyond the middle 90% (a walk, a slow start) are drawn at the axis's edge rather than
        // stretching the axis.
        let clamped = points.map { Point(elapsed: $0.elapsed, value: min(max($0.value, domain.lowerBound), domain.upperBound), segment: $0.segment) }
        return (clamped, domain)
    }

    /// The recorded steps as spans of the time axis, each with the role the plan gives it when the
    /// steps could be laid over `workout`.
    private static func stepSpans(of activity: Activity, workout: StructuredWorkout?, duration: TimeInterval) -> [StepSpan] {
        let recorded = activity.steps.sorted { $0.start < $1.start }
        guard !recorded.isEmpty else { return [] }
        var kinds: [Date: StepKind] = [:]
        if let workout, let aligned = ActivityStepAligner.align(recorded, with: workout) {
            let planned = workout.blocks.flatMap { block in
                (0..<max(block.repetitions, 1)).flatMap { _ in block.steps.map(\.kind) }
            }
            for (index, step) in aligned.enumerated() where index < planned.count {
                if let step { kinds[step.start] = planned[index] }
            }
        }
        return recorded.enumerated().compactMap { index, step in
            let start = max(0, step.start.timeIntervalSince(activity.start))
            let end = min(duration, step.end.timeIntervalSince(activity.start))
            guard end > start else { return nil }
            return StepSpan(id: index, kind: kinds[step.start], start: start, end: end)
        }
    }
}
