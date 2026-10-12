import Foundation
import TrainingCore

extension Activity {
    /// The recorded steps in the order they were performed (MVP2-146), the order that numbers them
    /// everywhere they are shown together: a chart's ``ActivityChartData/StepSpan/id`` and the step
    /// cards' ``WorkoutStepCard/recordedStepID`` are positions in this list, so tapping a card can
    /// highlight its span. Steps that start at the same instant are put in the Watch's own order.
    var orderedSteps: [ActivityStep] {
        steps.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return (lhs.block, lhs.repetition, lhs.step) < (rhs.block, rhs.repetition, rhs.step)
        }
    }
}

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
        /// `true` for the stretch after the last step (``ActivityAfterPlan``), which isn't a step of the
        /// plan: it is drawn grey and counted apart from the steps.
        public var isOutsidePlan = false
    }

    /// The most points either series is reduced to.
    public static let maximumPoints = 400
    /// Speed below this (meters a second, about 33 min/km) is a stop, not a pace.
    static let minimumMovingSpeed = 0.5
    /// A silence this long, in seconds, starts a new segment (longer for a source that records less
    /// often than every few seconds: see `gapThreshold(of:)`).
    static let gapSeconds: TimeInterval = 30
    /// How many speed samples (5 s each) the pace is averaged over, centred: 35 s.
    static let paceSmoothingSamples = 7

    /// Heart rate in beats per minute against time; empty without samples.
    public let heartRate: [Point]
    /// Pace in seconds per kilometer against time; empty without speed samples.
    public let pace: [Point]
    /// The recorded steps in order, then the stretch after the last one if there was one; empty for an
    /// activity with none.
    public let steps: [StepSpan]
    /// The activity's duration in seconds: the charts' time axis runs from 0 to this.
    public let duration: TimeInterval
    /// The range the pace axis covers, in seconds per kilometer (the larger number is the slower
    /// pace): the middle 90% of the pace readings, padded, so a stop or a walk doesn't squash the
    /// running. `nil` without pace.
    public let paceDomain: ClosedRange<Double>?

    /// How many of ``steps`` are steps of the plan, not the stretch after it.
    public var planStepCount: Int { steps.filter { !$0.isOutsidePlan }.count }

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

    /// One reading against time since the activity began, before it becomes a chart point.
    private struct Reading {
        let elapsed: TimeInterval
        let value: Double
    }

    /// The silence, in seconds, after which a new segment starts: ``gapSeconds``, or five times the
    /// readings' usual spacing when that is longer, so a source that records a heart rate a minute
    /// draws a line instead of a row of one-point segments.
    private static func gapThreshold(of readings: [Reading]) -> TimeInterval {
        var intervals: [TimeInterval] = []
        intervals.reserveCapacity(readings.count)
        for index in readings.indices.dropFirst() {
            let interval = readings[index].elapsed - readings[index - 1].elapsed
            if interval > 0 { intervals.append(interval) }
        }
        guard !intervals.isEmpty else { return gapSeconds }
        intervals.sort()
        let median = intervals[intervals.count / 2]
        return max(gapSeconds, median * 5)
    }

    /// Heart rate averaged into buckets of `duration / maximumPoints` seconds (at least a second), a
    /// new segment after any silence (see ``gapThreshold(of:)``).
    private static func heartRatePoints(_ samples: [HeartRateSample], start: Date, duration: TimeInterval) -> [Point] {
        var readings: [Reading] = []
        readings.reserveCapacity(samples.count)
        for sample in samples {
            let elapsed = sample.time.timeIntervalSince(start)
            guard elapsed >= 0, elapsed <= duration, sample.bpm.isFinite, sample.bpm > 0 else { continue }
            readings.append(Reading(elapsed: elapsed, value: sample.bpm))
        }
        readings.sort { $0.elapsed < $1.elapsed }
        guard !readings.isEmpty else { return [] }

        let gap = gapThreshold(of: readings)
        let bucket = max(duration / Double(maximumPoints), 1)
        var points: [Point] = []
        var segment = 0
        var bucketIndex = 0
        var elapsedSum = 0.0
        var valueSum = 0.0
        var count = 0
        var last = readings[0].elapsed

        func flush() {
            guard count > 0 else { return }
            points.append(Point(elapsed: elapsedSum / Double(count), value: valueSum / Double(count), segment: segment))
            elapsedSum = 0
            valueSum = 0
            count = 0
        }
        for reading in readings {
            if reading.elapsed - last > gap {
                flush()
                segment += 1
            }
            last = reading.elapsed
            let index = Int(reading.elapsed / bucket)
            if index != bucketIndex {
                flush()
                bucketIndex = index
            }
            elapsedSum += reading.elapsed
            valueSum += reading.value
            count += 1
        }
        flush()
        return points
    }

    /// Pace from speed, averaged over the ``paceSmoothingSamples`` samples around each one that are
    /// close in time to it (the stored samples are 5 s windows, so close is within half the smoothing
    /// span), so a stop doesn't drag in the running either side of it. A stop (below
    /// ``minimumMovingSpeed``) or a silence (see ``gapThreshold(of:)``) starts a new segment.
    private static func pacePoints(
        _ samples: [SpeedSample], start: Date, duration: TimeInterval
    ) -> ([Point], ClosedRange<Double>?) {
        var readings: [Reading] = []
        readings.reserveCapacity(samples.count)
        for sample in samples {
            let elapsed = sample.time.timeIntervalSince(start)
            guard elapsed >= 0, elapsed <= duration, sample.metersPerSecond.isFinite, sample.metersPerSecond >= 0 else { continue }
            readings.append(Reading(elapsed: elapsed, value: sample.metersPerSecond))
        }
        readings.sort { $0.elapsed < $1.elapsed }
        guard !readings.isEmpty else { return ([], nil) }

        let gap = gapThreshold(of: readings)
        let half = paceSmoothingSamples / 2
        let reach = Double(half) * 5 + 1
        var points: [Point] = []
        var segment = 0
        var broken = false
        var previous = readings[0].elapsed
        for index in readings.indices {
            let reading = readings[index]
            if reading.elapsed - previous > gap { broken = true }
            previous = reading.elapsed
            var sum = 0.0
            var members = 0
            for neighbour in max(0, index - half)...min(readings.count - 1, index + half)
            where abs(readings[neighbour].elapsed - reading.elapsed) <= reach {
                sum += readings[neighbour].value
                members += 1
            }
            let mean = sum / Double(members)
            guard mean >= minimumMovingSpeed else {
                broken = true
                continue
            }
            if broken {
                if !points.isEmpty { segment += 1 }
                broken = false
            }
            points.append(Point(elapsed: reading.elapsed, value: 1000 / mean, segment: segment))
        }
        guard points.count > 1 else { return (points, nil) }

        var values = points.map(\.value)
        values.sort()
        let low = values[Int(Double(values.count - 1) * 0.05)]
        let high = values[Int(Double(values.count - 1) * 0.95)]
        let pad = max((high - low) * 0.1, 10)
        let domain = (low - pad)...(high + pad)
        // Values beyond the middle 90% (a walk, a slow start) are drawn at the axis's edge rather than
        // stretching the axis.
        var clamped: [Point] = []
        clamped.reserveCapacity(points.count)
        for point in points {
            let value = min(max(point.value, domain.lowerBound), domain.upperBound)
            clamped.append(Point(elapsed: point.elapsed, value: value, segment: point.segment))
        }
        return (clamped, domain)
    }

    /// The recorded steps as spans of the time axis, each with the role the plan gives it when the
    /// steps could be laid over `workout`.
    private static func stepSpans(of activity: Activity, workout: StructuredWorkout?, duration: TimeInterval) -> [StepSpan] {
        let recorded = activity.orderedSteps
        guard !recorded.isEmpty else { return [] }
        var kinds: [ActivityStep: StepKind] = [:]
        if let workout, let aligned = ActivityStepAligner.align(recorded, with: workout) {
            let planned = workout.blocks.flatMap { block in
                (0..<max(block.repetitions, 1)).flatMap { _ in block.steps.map(\.kind) }
            }
            for (index, step) in aligned.enumerated() where index < planned.count {
                if let step { kinds[step] = planned[index] }
            }
        }
        var spans: [StepSpan] = recorded.enumerated().compactMap { index, step in
            let start = max(0, step.start.timeIntervalSince(activity.start))
            let end = min(duration, step.end.timeIntervalSince(activity.start))
            guard end > start else { return nil }
            return StepSpan(id: index, kind: kinds[step], start: start, end: end)
        }
        // The time after the last step, as a stretch of its own (MVP2-146).
        if let after = ActivityAfterPlan.make(for: activity) {
            spans.append(StepSpan(id: after.id, kind: nil, start: after.start, end: after.end, isOutsidePlan: true))
        }
        return spans
    }
}
