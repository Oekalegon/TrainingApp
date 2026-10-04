import Foundation
import TrainingCore

/// What the athlete's completed activities say about the paces they actually run (MVP2-35,
/// MVP2-111): for each activity, the time and distance spent in each heart-rate zone and, for an
/// activity linked to a planned workout, the time and distance of each of that workout's steps.
///
/// ``HistoricalPaceEstimator`` turns this into a planned workout's expected duration and distance,
/// in place of the fixed threshold-pace table of ``AthleteProfile/paceModel``.
///
/// Built from the speed and heart-rate streams, so an activity without either (a manual entry, a
/// treadmill run with no speed samples) contributes nothing.
public struct PaceHistory: Sendable, Equatable {
    /// Seconds and meters covered, which together give a pace.
    struct Sample: Sendable, Equatable {
        var seconds: Double = 0
        var meters: Double = 0

        static func += (lhs: inout Sample, rhs: Sample) {
            lhs.seconds += rhs.seconds
            lhs.meters += rhs.meters
        }
    }

    /// Where a step sits in its workout: the block's index and the step's index within the block.
    /// Repetitions of a block share a position.
    struct StepPosition: Sendable, Hashable {
        let block: Int
        let step: Int
    }

    /// One planned step as it was actually run.
    struct StepObservation: Sendable, Equatable {
        let position: StepPosition
        let kind: StepKind
        /// The zone the step targeted (not the zone the heart rate reached), so a recovery jog
        /// planned in zone 2 is compared with other zone-2 recoveries even when the heart rate was
        /// still high from the interval before it.
        let zone: Int
        /// `true` for a `.open` step, whose duration is only known from the activity.
        let isOpen: Bool
        let sample: Sample
    }

    /// One completed activity's pace evidence.
    struct Observation: Sendable, Equatable {
        let activityID: UUID
        let start: Date
        let sport: Sport
        let duration: TimeInterval
        /// Time and distance per heart-rate zone (1...5), from the speed stream binned by the heart
        /// rate at each moment.
        let zones: [Int: Sample]
        /// The workout of the plan the activity is linked to, if any.
        let workoutID: UUID?
        let templateID: UUID?
        /// The linked workout's steps, in order with repetitions expanded; empty when the activity
        /// isn't linked or has no speed stream to place the steps in.
        let steps: [StepObservation]

        /// Total seconds over all zones.
        var zoneSeconds: Double { zones.values.reduce(0) { $0 + $1.seconds } }
    }

    let observations: [Observation]

    /// An empty history — every estimate falls back to the athlete's pace model.
    public static let empty = PaceHistory(observations: [])

    init(observations: [Observation]) {
        self.observations = observations
    }

    /// Builds the history from `activities`.
    ///
    /// - Parameters:
    ///   - activities: The completed activities to learn from.
    ///   - plans: Plans the activities may be linked to (via ``Activity/linkedPlanID``).
    ///   - workouts: The workout library, for the linked plans' steps.
    ///   - athlete: Supplies the heart-rate zones in effect on each activity's day.
    ///   - gapThresholdSeconds: Samples further apart than this are a pause, not a stretch of running.
    public init(
        activities: [Activity], plans: [PlannedActivity], workouts: [StructuredWorkout],
        athlete: AthleteProfile, gapThresholdSeconds: TimeInterval
    ) {
        let plansByID = Dictionary(plans.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let workoutsByID = Dictionary(workouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        observations = activities.compactMap { activity in
            let workout = activity.linkedPlanID
                .flatMap { plansByID[$0] }
                .flatMap { workoutsByID[$0.workoutID] }
            return Self.observation(for: activity, workout: workout, athlete: athlete, gapThresholdSeconds: gapThresholdSeconds)
        }
    }

    /// `activity`'s pace evidence, or `nil` when it has no usable speed or heart-rate stream, or no
    /// zone settings were in effect that day.
    static func observation(
        for activity: Activity, workout: StructuredWorkout?, athlete: AthleteProfile,
        gapThresholdSeconds: TimeInterval
    ) -> Observation? {
        guard activity.speed.count > 1, !activity.heartRate.isEmpty,
              let settings = athlete.heartRateZoneSettings(asOf: activity.start)
        else { return nil }
        let zoneModel = HeartRateZoneModel(settings: settings)
        guard let bpmBoundaries = ZoneBoundaries(bpmOf: zoneModel),
              let ratioBoundaries = ZoneBoundaries(ratioOf: zoneModel)
        else { return nil }

        let speed = activity.speed.sorted { $0.time < $1.time }
        let heartRate = activity.heartRate.sorted { $0.time < $1.time }
        let track = DistanceTrack(speed: speed, gapThresholdSeconds: gapThresholdSeconds)

        var zones: [Int: Sample] = [:]
        for segment in track.segments where segment.meters / segment.seconds >= minimumMovingSpeed {
            let midpoint = segment.start.addingTimeInterval(segment.seconds / 2)
            guard let bpm = interpolatedBPM(heartRate, at: midpoint, gapThresholdSeconds: gapThresholdSeconds) else { continue }
            let zone = bpmBoundaries.zone(for: bpm)
            guard zone >= 1 else { continue }
            zones[zone, default: Sample()] += Sample(seconds: segment.seconds, meters: segment.meters)
        }
        guard !zones.isEmpty else { return nil }

        var steps: [StepObservation] = []
        if let workout, workout.sport.isSameFamily(as: activity.sport) {
            steps = stepObservations(
                workout: workout, activity: activity, track: track,
                zoneModel: zoneModel, ratioBoundaries: ratioBoundaries
            )
        }

        return Observation(
            activityID: activity.id, start: activity.start, sport: activity.sport, duration: activity.duration,
            zones: zones, workoutID: workout?.id, templateID: workout?.templateID, steps: steps
        )
    }

    /// Slower than this (1.8 km/h) is standing still or walking to a stop, not running at a pace.
    static let minimumMovingSpeed = 0.5

    /// Lays `workout`'s steps over `activity` in order. A `.time` step ends after its time and a
    /// `.distance` step once the speed stream has covered its distance; `.open` steps share the time
    /// the other steps leave over, which is the only way to tell where a lap-button step ended
    /// without lap data.
    private static func stepObservations(
        workout: StructuredWorkout, activity: Activity, track: DistanceTrack,
        zoneModel: HeartRateZoneModel, ratioBoundaries: ZoneBoundaries
    ) -> [StepObservation] {
        let expanded = expandedSteps(of: workout)
        guard !expanded.isEmpty, activity.duration > 0 else { return [] }

        let activityEnd = activity.start.addingTimeInterval(activity.duration)
        let averageSpeed = track.totalMeters / activity.duration
        var knownSeconds = 0.0
        var openCount = 0
        for (_, step) in expanded {
            switch step.goal {
            case .time(let seconds): knownSeconds += seconds
            case .distance(let meters): knownSeconds += averageSpeed > 0 ? meters / averageSpeed : 0
            case .open: openCount += 1
            }
        }
        let openSeconds = openCount > 0 ? max(0, (activity.duration - knownSeconds) / Double(openCount)) : 0

        var observations: [StepObservation] = []
        var cursor = activity.start
        for (position, step) in expanded {
            var end: Date
            switch step.goal {
            case .time(let seconds):
                end = cursor.addingTimeInterval(seconds)
            case .distance(let meters):
                end = track.time(reaching: track.meters(at: cursor) + meters) ?? activityEnd
            case .open:
                end = cursor.addingTimeInterval(openSeconds)
            }
            end = min(end, activityEnd)
            let seconds = end.timeIntervalSince(cursor)
            guard seconds > 0 else { break }
            let ratio = zoneModel.intensityRatio(for: step.target)
            observations.append(StepObservation(
                position: position, kind: step.kind, zone: max(ratioBoundaries.zone(for: ratio), 1),
                isOpen: step.goal == .open,
                sample: Sample(seconds: seconds, meters: track.meters(at: end) - track.meters(at: cursor))
            ))
            cursor = end
        }
        return observations
    }

    /// `workout`'s steps in the order they're run, with block repetitions expanded.
    static func expandedSteps(of workout: StructuredWorkout) -> [(position: StepPosition, step: WorkoutStep)] {
        var steps: [(position: StepPosition, step: WorkoutStep)] = []
        for (blockIndex, block) in workout.blocks.enumerated() where block.repetitions > 0 {
            for _ in 0..<block.repetitions {
                for (stepIndex, step) in block.steps.enumerated() {
                    steps.append((StepPosition(block: blockIndex, step: stepIndex), step))
                }
            }
        }
        return steps
    }

    /// The heart rate at `time`, interpolated between the samples either side of it; `nil` when no
    /// sample is close enough to say.
    static func interpolatedBPM(_ samples: [HeartRateSample], at time: Date, gapThresholdSeconds: TimeInterval) -> Double? {
        var low = 0
        var high = samples.count
        while low < high {
            let mid = (low + high) / 2
            if samples[mid].time < time { low = mid + 1 } else { high = mid }
        }
        let after = low < samples.count ? samples[low] : nil
        let before = low > 0 ? samples[low - 1] : nil
        switch (before, after) {
        case let (before?, after?) where after.time.timeIntervalSince(before.time) <= gapThresholdSeconds:
            let span = after.time.timeIntervalSince(before.time)
            guard span > 0 else { return after.bpm }
            let fraction = time.timeIntervalSince(before.time) / span
            return before.bpm + (after.bpm - before.bpm) * fraction
        default:
            let nearest = [before, after].compactMap { $0 }
                .min { abs($0.time.timeIntervalSince(time)) < abs($1.time.timeIntervalSince(time)) }
            guard let nearest, abs(nearest.time.timeIntervalSince(time)) <= gapThresholdSeconds / 2 else { return nil }
            return nearest.bpm
        }
    }
}

/// The edges of zones 1...5 — in bpm or in heart-rate-reserve ratio — for finding which zone a
/// value falls in. Below zone 1 is zone 0; at or above zone 5's top is zone 5.
struct ZoneBoundaries: Sendable {
    /// `[z1.lower, z1.upper, z2.upper, z3.upper, z4.upper, z5.upper]`.
    let edges: [Double]

    init?(bpmOf model: HeartRateZoneModel) {
        self.init((1...5).map { model.zoneBPMRange($0) })
    }

    init?(ratioOf model: HeartRateZoneModel) {
        self.init((1...5).map { model.zoneRatioRange($0) })
    }

    private init?(_ ranges: [ClosedRange<Double>?]) {
        let ranges = ranges.compactMap { $0 }
        guard ranges.count == 5, let first = ranges.first else { return nil }
        edges = [first.lowerBound] + ranges.map(\.upperBound)
    }

    func zone(for value: Double) -> Int {
        guard value >= edges[0] else { return 0 }
        for index in 1..<edges.count where value < edges[index] {
            return index
        }
        return 5
    }
}

/// Distance covered over time, integrated from a speed stream.
struct DistanceTrack: Sendable {
    /// A stretch between two consecutive speed samples.
    struct Segment: Sendable {
        let start: Date
        let seconds: Double
        let meters: Double
    }

    /// Each sample's time and the meters covered up to it.
    private let times: [Date]
    private let cumulativeMeters: [Double]
    let segments: [Segment]

    /// Integrates `speed` (sorted by time) with the trapezoid rule; a gap longer than
    /// `gapThresholdSeconds` adds no distance.
    init(speed: [SpeedSample], gapThresholdSeconds: TimeInterval) {
        var times: [Date] = []
        var cumulative: [Double] = []
        var segments: [Segment] = []
        var total = 0.0
        for (index, sample) in speed.enumerated() {
            if index > 0 {
                let previous = speed[index - 1]
                let seconds = sample.time.timeIntervalSince(previous.time)
                if seconds > 0, seconds <= gapThresholdSeconds {
                    let meters = max(0, (previous.metersPerSecond + sample.metersPerSecond) / 2 * seconds)
                    total += meters
                    segments.append(Segment(start: previous.time, seconds: seconds, meters: meters))
                }
            }
            times.append(sample.time)
            cumulative.append(total)
        }
        self.times = times
        self.cumulativeMeters = cumulative
        self.segments = segments
    }

    var totalMeters: Double { cumulativeMeters.last ?? 0 }

    /// Meters covered by `time`, interpolated between samples and clamped to the stream's ends.
    func meters(at time: Date) -> Double {
        guard let first = times.first, let last = times.last else { return 0 }
        if time <= first { return 0 }
        if time >= last { return totalMeters }
        var low = 0
        var high = times.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if times[mid] <= time { low = mid } else { high = mid }
        }
        let span = times[high].timeIntervalSince(times[low])
        guard span > 0 else { return cumulativeMeters[high] }
        let fraction = time.timeIntervalSince(times[low]) / span
        return cumulativeMeters[low] + (cumulativeMeters[high] - cumulativeMeters[low]) * fraction
    }

    /// When the distance covered first reaches `meters`, or `nil` if it never does.
    func time(reaching meters: Double) -> Date? {
        guard let index = cumulativeMeters.firstIndex(where: { $0 >= meters }) else { return nil }
        guard index > 0 else { return times[0] }
        let previous = cumulativeMeters[index - 1]
        let gained = cumulativeMeters[index] - previous
        guard gained > 0 else { return times[index] }
        let fraction = (meters - previous) / gained
        return times[index - 1].addingTimeInterval(times[index].timeIntervalSince(times[index - 1]) * fraction)
    }
}
