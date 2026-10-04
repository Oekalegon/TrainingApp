import Foundation
import TrainingCore

/// A planned workout's expected duration and distance from ``HistoricalPaceEstimator``.
public struct HistoricalProjection: Sendable, Equatable {
    /// Expected duration in seconds.
    public let duration: TimeInterval
    /// Expected distance in meters; `nil` when the athlete has no heart-rate zone settings, so a
    /// step's zone (and with it its pace) is unknown.
    public let distanceMeters: Double?
    /// How many earlier activities the paces were learned from. `0` means the athlete's pace model
    /// alone.
    public let matchedActivityCount: Int
}

/// Estimates how long and how far a planned workout will be from the athlete's earlier workouts
/// that resemble it (MVP2-35, MVP2-111), instead of from a fixed pace table alone.
///
/// 1. **Match.** Every earlier activity of the same sport family is scored on how closely its time
///    in each heart-rate zone matches the planned workout's, how close its duration is, how recent
///    it is, and whether it ran the same workout or a workout from the same template. The best
///    ``maximumMatches`` are kept; an activity whose zone mix overlaps less than
///    ``minimumZoneOverlap`` isn't similar at all.
/// 2. **Pace per zone.** The matches' time and distance in each zone give a pace per zone, pulled
///    towards ``AthleteProfile/paceModel``'s pace by ``priorSeconds`` of pretend evidence so a few
///    seconds in a zone can't swing it, and kept slower in lower zones than in higher ones: zone 1
///    is never faster than zone 4. The model's paces are first scaled by how much faster or slower
///    the matches were overall, so zones the matches didn't reach move along with those they did.
/// 3. **Pace per step.** For matches linked to a plan, each step was laid over the recording (see
///    ``PaceHistory``). A planned step takes the pace earlier steps of the same kind and zone were
///    run at, favouring steps of similar length (a 400 m rep is run faster than a 2 km one), pulled
///    towards the zone's pace the same way. This is what keeps a zone-2 recovery jog between
///    intervals, run while the heart rate is still coming down, from being treated like a
///    zone-2 steady run.
/// 4. **Open steps.** An `.open` step (the run to the hill in hill sprints) takes the median time
///    the same step took in earlier runs of the same workout or template, else the duration
///    estimator's default.
///
/// A `.time` step's distance and a `.distance` step's time then follow from its pace.
public struct HistoricalPaceEstimator: Sendable {
    /// Seconds of evidence the prior pace counts as; more observed time than this outweighs it.
    public var priorSeconds: Double = 300
    /// After this many days an activity counts half as much as one from today.
    public var recencyHalfLifeDays: Double = 60
    /// How many similar activities are used.
    public var maximumMatches = 12
    /// The least share of time-in-zone an activity must have in common with the planned workout.
    public var minimumZoneOverlap = 0.5
    /// Turns step goals into durations when nothing better is known; also supplies the default
    /// `.open` step duration.
    public var durationEstimator: WorkoutDurationEstimator

    /// Creates an estimator.
    ///
    /// - Parameter durationEstimator: The fallback for step durations, normally the statistics
    ///   calculator's, so an estimate without history agrees with the week's totals.
    public init(durationEstimator: WorkoutDurationEstimator = WorkoutDurationEstimator()) {
        self.durationEstimator = durationEstimator
    }

    /// One planned step with the zone and kind its pace is looked up by.
    private struct PlannedStep {
        let position: PaceHistory.StepPosition
        let step: WorkoutStep
        let zone: Int
        /// Duration at the prior pace — used to weigh the zone mix and step lengths before the
        /// learned paces are known.
        let priorSeconds: Double
    }

    /// The expected duration and distance of `workout`, learned from `history`.
    ///
    /// - Parameters:
    ///   - workout: The planned workout.
    ///   - athlete: Supplies current zone settings and the prior pace model.
    ///   - history: Earlier activities.
    ///   - cutoff: Only activities that started before this are used — a planned day's own activity
    ///     (or a later one) mustn't inform its own forecast.
    ///   - excludedActivityID: An activity to leave out, e.g. the one the plan is linked to.
    public func projection(
        for workout: StructuredWorkout, athlete: AthleteProfile, history: PaceHistory,
        before cutoff: Date, excluding excludedActivityID: UUID? = nil
    ) -> HistoricalProjection {
        guard let settings = athlete.currentHeartRateZoneSettings,
              let ratioBoundaries = ZoneBoundaries(ratioOf: HeartRateZoneModel(settings: settings))
        else {
            return HistoricalProjection(
                duration: durationEstimator.duration(for: workout, athlete: athlete),
                distanceMeters: nil, matchedActivityCount: 0
            )
        }
        let zoneModel = HeartRateZoneModel(settings: settings)
        let priorSpeeds = Dictionary(uniqueKeysWithValues: (1...5).map {
            ($0, 1 / athlete.paceModel.secondsPerMeter(atZone: $0))
        })

        let planned = PaceHistory.expandedSteps(of: workout).map { position, step -> PlannedStep in
            let zone = max(ratioBoundaries.zone(for: zoneModel.intensityRatio(for: step.target)), 1)
            let seconds: Double
            switch step.goal {
            case .time(let interval): seconds = interval
            case .distance(let meters): seconds = meters / (priorSpeeds[zone] ?? 1)
            case .open: seconds = durationEstimator.defaultOpenStepDuration
            }
            return PlannedStep(position: position, step: step, zone: zone, priorSeconds: seconds)
        }

        let candidates = history.observations.filter {
            $0.start < cutoff && $0.activityID != excludedActivityID && $0.sport.isSameFamily(as: workout.sport)
        }
        let matches = self.matches(for: workout, planned: planned, among: candidates, asOf: cutoff)
        let zoneSpeeds = self.zoneSpeeds(matches: matches, priorSpeeds: priorSpeeds)
        let openDurations = self.openStepDurations(for: workout, among: candidates)

        var duration = 0.0
        var distance = 0.0
        for plannedStep in planned {
            let speed = stepSpeed(for: plannedStep, matches: matches, zoneSpeed: zoneSpeeds[plannedStep.zone] ?? 1)
            switch plannedStep.step.goal {
            case .time(let seconds):
                duration += seconds
                distance += seconds * speed
            case .distance(let meters):
                duration += meters / speed
                distance += meters
            case .open:
                let seconds = openDurations[plannedStep.position] ?? durationEstimator.defaultOpenStepDuration
                duration += seconds
                distance += seconds * speed
            }
        }
        return HistoricalProjection(duration: duration, distanceMeters: distance, matchedActivityCount: matches.count)
    }

    // MARK: - Matching

    /// The most similar candidates with their weights, best first.
    private func matches(
        for workout: StructuredWorkout, planned: [PlannedStep],
        among candidates: [PaceHistory.Observation], asOf date: Date
    ) -> [(observation: PaceHistory.Observation, weight: Double)] {
        let plannedTotal = planned.reduce(0) { $0 + $1.priorSeconds }
        guard plannedTotal > 0 else { return [] }
        var plannedShare: [Int: Double] = [:]
        for step in planned {
            plannedShare[step.zone, default: 0] += step.priorSeconds / plannedTotal
        }

        let scored: [(observation: PaceHistory.Observation, weight: Double)] = candidates.compactMap {
            observation -> (observation: PaceHistory.Observation, weight: Double)? in
            let total = observation.zoneSeconds
            guard total > 0 else { return nil }
            let overlap = (1...5).reduce(0.0) { sum, zone in
                sum + min(plannedShare[zone] ?? 0, (observation.zones[zone]?.seconds ?? 0) / total)
            }
            guard overlap >= minimumZoneOverlap else { return nil }
            let durationSimilarity = Self.similarity(plannedTotal, observation.duration)
            let ageDays = max(0, date.timeIntervalSince(observation.start) / 86_400)
            let recency = pow(0.5, ageDays / recencyHalfLifeDays)
            let structure: Double
            if observation.workoutID == workout.id {
                structure = 3
            } else if let templateID = workout.templateID, observation.templateID == templateID {
                structure = 2
            } else {
                structure = 1
            }
            return (observation, overlap * overlap * durationSimilarity * recency * structure)
        }
        return Array(scored.sorted { $0.weight > $1.weight }.prefix(maximumMatches))
    }

    /// `min / max` of two positive amounts: 1 when equal, towards 0 as they diverge.
    static func similarity(_ a: Double, _ b: Double) -> Double {
        guard a > 0, b > 0 else { return 0 }
        return min(a, b) / max(a, b)
    }

    // MARK: - Paces

    /// Speed (m/s) per zone 1...5 from the matches, shrunk towards the prior and made to rise with
    /// the zone.
    private func zoneSpeeds(
        matches: [(observation: PaceHistory.Observation, weight: Double)], priorSpeeds: [Int: Double]
    ) -> [Int: Double] {
        var evidence: [Int: PaceHistory.Sample] = [:]
        for zone in 1...5 {
            for (observation, weight) in matches {
                guard let sample = observation.zones[zone] else { continue }
                evidence[zone, default: PaceHistory.Sample()] += PaceHistory.Sample(
                    seconds: sample.seconds * weight, meters: sample.meters * weight
                )
            }
        }

        // How much faster (or slower) than the pace model the athlete ran overall, itself pulled
        // towards 1 by `priorSeconds` at an average prior pace. It scales every zone's prior, so a
        // zone with no evidence of its own follows the zones that have it: an athlete 20 % faster
        // than the model at zone 4 is likely faster at zone 5 too, and an unscaled zone-5 prior
        // would otherwise drag zone 4 back down when the zones are made to rise.
        let averagePrior = (1...5).reduce(0.0) { $0 + (priorSpeeds[$1] ?? 1) } / 5
        let observedMeters = evidence.values.reduce(0.0) { $0 + $1.meters }
        let expectedMeters = evidence.reduce(0.0) { $0 + $1.value.seconds * (priorSpeeds[$1.key] ?? 1) }
        let scale = (observedMeters + priorSeconds * averagePrior) / (expectedMeters + priorSeconds * averagePrior)

        var speeds: [Double] = []
        var weights: [Double] = []
        for zone in 1...5 {
            let zoneEvidence = evidence[zone] ?? PaceHistory.Sample()
            let prior = (priorSpeeds[zone] ?? 1) * scale
            speeds.append((zoneEvidence.meters + priorSeconds * prior) / (zoneEvidence.seconds + priorSeconds))
            weights.append(zoneEvidence.seconds + priorSeconds)
        }
        let monotone = Self.nonDecreasing(speeds, weights: weights)
        return Dictionary(uniqueKeysWithValues: monotone.enumerated().map { ($0.offset + 1, $0.element) })
    }

    /// Speed (m/s) for one planned step: earlier steps of the same kind and zone, weighted by their
    /// activity's match weight and by how close their length is, shrunk towards `zoneSpeed`.
    private func stepSpeed(
        for planned: PlannedStep, matches: [(observation: PaceHistory.Observation, weight: Double)],
        zoneSpeed: Double
    ) -> Double {
        var evidence = PaceHistory.Sample()
        for (observation, weight) in matches {
            for step in observation.steps where step.kind == planned.step.kind && step.zone == planned.zone {
                guard step.sample.seconds > 0 else { continue }
                let lengthSimilarity: Double
                switch planned.step.goal {
                case .distance(let meters): lengthSimilarity = Self.similarity(meters, step.sample.meters)
                case .time, .open: lengthSimilarity = Self.similarity(planned.priorSeconds, step.sample.seconds)
                }
                let stepWeight = weight * lengthSimilarity
                evidence += PaceHistory.Sample(seconds: step.sample.seconds * stepWeight, meters: step.sample.meters * stepWeight)
            }
        }
        let speed = (evidence.meters + priorSeconds * zoneSpeed) / (evidence.seconds + priorSeconds)
        return speed > 0 ? speed : zoneSpeed
    }

    /// The median observed duration of each `.open` step of `workout`, from earlier runs of the same
    /// workout or, failing that, of workouts made from the same template (whose blocks and steps sit
    /// in the same places whatever its parameter values).
    private func openStepDurations(
        for workout: StructuredWorkout, among candidates: [PaceHistory.Observation]
    ) -> [PaceHistory.StepPosition: Double] {
        let sameWorkout = candidates.filter { $0.workoutID == workout.id }
        let sameTemplate = workout.templateID.map { templateID in
            candidates.filter { $0.templateID == templateID }
        } ?? []
        let source = sameWorkout.contains { $0.steps.contains(where: \.isOpen) } ? sameWorkout : sameTemplate

        var observed: [PaceHistory.StepPosition: [Double]] = [:]
        for observation in source {
            for step in observation.steps where step.isOpen {
                observed[step.position, default: []].append(step.sample.seconds)
            }
        }
        return observed.compactMapValues(Self.median)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// The weighted least-squares non-decreasing fit to `values` (pool adjacent violators): wherever
    /// a lower zone came out faster than a higher one, both get their weighted average.
    static func nonDecreasing(_ values: [Double], weights: [Double]) -> [Double] {
        var blocks: [(value: Double, weight: Double, count: Int)] = []
        for (value, weight) in zip(values, weights) {
            blocks.append((value, weight, 1))
            while blocks.count > 1, blocks[blocks.count - 2].value > blocks[blocks.count - 1].value {
                let upper = blocks.removeLast()
                let lower = blocks.removeLast()
                let weight = lower.weight + upper.weight
                let value = weight > 0 ? (lower.value * lower.weight + upper.value * upper.weight) / weight : lower.value
                blocks.append((value, weight, lower.count + upper.count))
            }
        }
        return blocks.flatMap { Array(repeating: $0.value, count: $0.count) }
    }
}
