import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

/// Forecasting a planned workout's duration and distance from earlier workouts (MVP2-35, MVP2-111).
///
/// The athlete has resting 50 / max 190 bpm under Karvonen zones, so zone 1 is 120–134 bpm, zone 2
/// 134–148, zone 3 148–162, zone 4 162–176 and zone 5 176–190. Their pace model has a 300 s/km
/// threshold pace: zone 2 is 360 s/km (2.78 m/s), zone 4 300 s/km (3.33 m/s).
@MainActor
@Suite("HistoricalPaceEstimator (MVP2-35, MVP2-111)")
struct HistoricalPaceEstimatorTests {
    private let athlete = AthleteProfile.fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 190)
    private let estimator = HistoricalPaceEstimator()
    private let gap: TimeInterval = 30

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    /// An activity made of back-to-back phases of steady speed and heart rate, sampled every 5 s.
    private func activity(
        start: Date, sport: Sport = .running, linkedPlanID: UUID? = nil,
        phases: [(seconds: Double, metersPerSecond: Double, bpm: Double)]
    ) -> Activity {
        var speed: [SpeedSample] = []
        var heartRate: [HeartRateSample] = []
        var offset = 0.0
        var meters = 0.0
        for phase in phases {
            for t in stride(from: 0.0, to: phase.seconds, by: 5) {
                let time = start.addingTimeInterval(offset + t)
                speed.append(SpeedSample(time: time, metersPerSecond: phase.metersPerSecond))
                heartRate.append(HeartRateSample(time: time, bpm: phase.bpm))
            }
            offset += phase.seconds
            meters += phase.seconds * phase.metersPerSecond
        }
        let end = start.addingTimeInterval(offset)
        speed.append(SpeedSample(time: end, metersPerSecond: phases.last?.metersPerSecond ?? 0))
        heartRate.append(HeartRateSample(time: end, bpm: phases.last?.bpm ?? 0))
        return Activity(
            source: .healthKit(UUID()), sport: sport, start: start, duration: offset,
            distanceMeters: meters, heartRate: heartRate, speed: speed, linkedPlanID: linkedPlanID
        )
    }

    private func steadyWorkout(minutes: Double, zone: Int) -> StructuredWorkout {
        StructuredWorkout(
            name: "Run", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(minutes * 60), target: .heartRateZone(zone))])]
        )
    }

    private func history(_ activities: [Activity], plans: [PlannedActivity] = [], workouts: [StructuredWorkout] = []) -> PaceHistory {
        PaceHistory(activities: activities, plans: plans, workouts: workouts, athlete: athlete, gapThresholdSeconds: gap)
    }

    private func speed(of projection: HistoricalProjection) -> Double {
        (projection.distanceMeters ?? 0) / projection.duration
    }

    // MARK: - Fallback

    @Test("without history the forecast is the pace model's")
    func emptyHistoryUsesPaceModel() {
        let projection = estimator.projection(
            for: steadyWorkout(minutes: 20, zone: 2), athlete: athlete, history: .empty, before: day(10)
        )

        #expect(projection.duration == 1200)
        #expect(abs((projection.distanceMeters ?? 0) - 1200 / 0.36) < 0.5)
        #expect(projection.matchedActivityCount == 0)
    }

    @Test("without zone settings there's a duration but no distance")
    func noZonesNoDistance() {
        let projection = estimator.projection(
            for: steadyWorkout(minutes: 20, zone: 2), athlete: .fixture(), history: .empty, before: day(10)
        )

        #expect(projection.duration == 1200)
        #expect(projection.distanceMeters == nil)
    }

    // MARK: - Zones

    @Test("a similar earlier run moves the forecast pace towards the pace actually run")
    func learnsZonePace() {
        let earlier = activity(start: day(3), phases: [(2400, 3.0, 141)])

        let projection = estimator.projection(
            for: steadyWorkout(minutes: 40, zone: 2), athlete: athlete, history: history([earlier]), before: day(10)
        )

        #expect(projection.matchedActivityCount == 1)
        // Between the pace model's 2.78 m/s and the 3.0 m/s run, much nearer the latter.
        #expect(speed(of: projection) > 2.9)
        #expect(speed(of: projection) < 3.0)
    }

    @Test("an easy run informs an easy plan and a hard run a hard one: zone 1 is forecast slower than zone 4")
    func zonesKeepTheirOwnPace() {
        let easy = activity(start: day(3), phases: [(2400, 2.5, 127)])
        let hard = activity(start: day(4), phases: [(1800, 4.0, 169)])
        let both = history([easy, hard])

        let easyProjection = estimator.projection(
            for: steadyWorkout(minutes: 40, zone: 1), athlete: athlete, history: both, before: day(10)
        )
        let hardProjection = estimator.projection(
            for: steadyWorkout(minutes: 30, zone: 4), athlete: athlete, history: both, before: day(10)
        )

        // Each matches only the run in its own zone.
        #expect(easyProjection.matchedActivityCount == 1)
        #expect(hardProjection.matchedActivityCount == 1)
        #expect(speed(of: easyProjection) < 2.6)
        #expect(speed(of: hardProjection) > 3.8)
    }

    @Test("a lower zone is never forecast faster than a higher one")
    func monotoneZones() {
        #expect(HistoricalPaceEstimator.nonDecreasing([3, 2.5, 3.5], weights: [1, 1, 1]) == [2.75, 2.75, 3.5])
        #expect(HistoricalPaceEstimator.nonDecreasing([1, 2, 3], weights: [1, 1, 1]) == [1, 2, 3])
        #expect(HistoricalPaceEstimator.nonDecreasing([4, 1], weights: [1, 3]) == [1.75, 1.75])
    }

    @Test("only earlier runs of the same sport count, and not the excluded one")
    func filtersCandidates() {
        let ride = activity(start: day(3), sport: .cycling, phases: [(2400, 8.0, 141)])
        let later = activity(start: day(12), phases: [(2400, 3.0, 141)])
        let excluded = activity(start: day(5), phases: [(2400, 3.0, 141)])

        let projection = estimator.projection(
            for: steadyWorkout(minutes: 40, zone: 2), athlete: athlete,
            history: history([ride, later, excluded]), before: day(10), excluding: excluded.id
        )

        #expect(projection.matchedActivityCount == 0)
        #expect(abs((projection.distanceMeters ?? 0) - 2400 / 0.36) < 0.5)
    }

    // MARK: - Steps

    /// 10 minutes warm-up in zone 2, then 5 × (3 minutes in zone 4, `recovery` seconds of recovery
    /// in zone 2).
    private func intervals(templateID: UUID, recovery: TimeInterval = 120) -> StructuredWorkout {
        StructuredWorkout(
            name: "Intervals", sport: .running,
            blocks: [
                WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(600), target: .heartRateZone(2))]),
                WorkoutBlock(steps: [
                    WorkoutStep(kind: .work, goal: .time(180), target: .heartRateZone(4)),
                    WorkoutStep(kind: .recovery, goal: .time(recovery), target: .heartRateZone(2))
                ], repetitions: 5)
            ],
            templateID: templateID
        )
    }

    @Test("each step is forecast at the pace that kind of step was run at, so a zone-2 recovery jog isn't forecast at steady zone-2 pace")
    func stepsKeepTheirOwnPace() {
        let templateID = UUID()
        let earlierWorkout = intervals(templateID: templateID)
        let earlierPlan = PlannedActivity(workoutID: earlierWorkout.id, date: day(3))
        // The recoveries were a slow 1.6 m/s jog, though in zone 2 like the 2.8 m/s warm-up.
        var phases: [(seconds: Double, metersPerSecond: Double, bpm: Double)] = [(600, 2.8, 141)]
        for _ in 0..<5 {
            phases.append((180, 4.2, 169))
            phases.append((120, 1.6, 145))
        }
        let earlierIntervals = activity(start: day(3), linkedPlanID: earlierPlan.id, phases: phases)
        let steadyRun = activity(start: day(4), phases: [(2400, 2.8, 141)])
        // The same session with 3-minute recoveries, as run before.
        let planned = intervals(templateID: templateID, recovery: 180)
        let expectedMeters = 600 * 2.8 + 5 * (180 * 4.2 + 180 * 1.6)

        let stepAware = estimator.projection(
            for: planned, athlete: athlete,
            history: history([earlierIntervals, steadyRun], plans: [earlierPlan], workouts: [earlierWorkout]),
            before: day(10)
        )
        // Unlinked, the intervals give zone paces only: the recoveries blend with the steady run.
        let zonesOnly = estimator.projection(
            for: planned, athlete: athlete, history: history([earlierIntervals, steadyRun]), before: day(10)
        )

        #expect(stepAware.duration == 2400)
        #expect(stepAware.matchedActivityCount == 2)
        let stepAwareError = abs((stepAware.distanceMeters ?? 0) - expectedMeters) / expectedMeters
        let zonesOnlyError = abs((zonesOnly.distanceMeters ?? 0) - expectedMeters) / expectedMeters
        #expect(stepAwareError < 0.035)
        #expect(stepAwareError + 0.02 < zonesOnlyError)
    }

    @Test("a linked activity's steps are laid over its recording")
    func stepObservations() throws {
        let workout = intervals(templateID: UUID())
        let plan = PlannedActivity(workoutID: workout.id, date: day(3))
        // Recovery jogs are slow while the heart rate is still up from the rep (zone 3 by bpm).
        var phases: [(seconds: Double, metersPerSecond: Double, bpm: Double)] = [(600, 2.8, 141)]
        for _ in 0..<5 {
            phases.append((180, 4.2, 169))
            phases.append((120, 2.2, 155))
        }
        let run = activity(start: day(3), linkedPlanID: plan.id, phases: phases)

        let observation = try #require(history([run], plans: [plan], workouts: [workout]).observations.first)

        #expect(observation.steps.count == 11)
        let work = observation.steps.filter { $0.kind == .work }
        #expect(work.count == 5)
        #expect(work.allSatisfy { $0.zone == 4 && abs($0.sample.seconds - 180) < 1e-3 })
        #expect(work.allSatisfy { abs($0.sample.meters / $0.sample.seconds - 4.2) < 0.1 })
    }

    // MARK: - Open steps (MVP2-111)

    /// Warm-up, an open run to the hill, 2 × 1 minute up it, and a cool-down.
    private func hillSprints(templateID: UUID) -> StructuredWorkout {
        StructuredWorkout(
            name: "Hills", sport: .running,
            blocks: [
                WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(600), target: .heartRateZone(2))]),
                WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .open, target: .heartRateZone(2))]),
                WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(60), target: .heartRateZone(4))], repetitions: 2),
                WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .time(600), target: .heartRateZone(2))])
            ],
            templateID: templateID
        )
    }

    @Test("an open step takes as long as it took in earlier runs of the same template")
    func openStepFromHistory() {
        let templateID = UUID()
        var activities: [Activity] = []
        var plans: [PlannedActivity] = []
        var workouts: [StructuredWorkout] = []
        // The fixed steps take 1320 s, so the open step took 900 s and 1100 s.
        for (index, total) in [2220.0, 2420.0].enumerated() {
            let workout = hillSprints(templateID: templateID)
            let plan = PlannedActivity(workoutID: workout.id, date: day(3 + index))
            workouts.append(workout)
            plans.append(plan)
            activities.append(activity(start: day(3 + index), linkedPlanID: plan.id, phases: [(total, 3.0, 141)]))
        }

        let withHistory = estimator.projection(
            for: hillSprints(templateID: templateID), athlete: athlete,
            history: history(activities, plans: plans, workouts: workouts), before: day(10)
        )
        let withoutHistory = estimator.projection(
            for: hillSprints(templateID: templateID), athlete: athlete, history: .empty, before: day(10)
        )

        #expect(abs(withHistory.duration - (1320 + 1000)) < 1)
        #expect(withoutHistory.duration == 1320 + 600)
    }

    // MARK: - Week view

    @Test("the week view reads earlier activities from the store and forecasts planned workouts from them")
    func weekViewForecastsFromStore() async throws {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(10))
        try await store.upsert([activity(start: day(3), phases: [(2400, 3.0, 141)])])
        let easy = steadyWorkout(minutes: 40, zone: 2)
        try await model.add(easy, asOf: day(10))
        let plan = PlannedActivity(workoutID: easy.id, date: day(10))
        try await model.add(plan, asOf: day(10))

        let before = viewModel.plannedWorkoutDetailViewModel(for: plan)
        #expect(before.forecastActivityCount == 0)
        #expect(abs((before.expectedDistanceMeters ?? 0) - 2400 / 0.36) < 0.5)

        await viewModel.refreshPaceHistoryIfNeeded(asOf: day(10))

        let after = viewModel.plannedWorkoutDetailViewModel(for: plan)
        #expect(viewModel.paceHistory.observations.count == 1)
        #expect(after.forecastActivityCount == 1)
        #expect((after.expectedDistanceMeters ?? 0) > 2400 * 2.9)
        #expect(after.forecastBasis == "Forecast from your pace in 1 similar workout.")
    }

    // MARK: - Building blocks

    @Test("an activity without a speed stream gives no pace evidence")
    func noSpeedNoObservation() {
        var run = activity(start: day(3), phases: [(1200, 3.0, 141)])
        run.speed = []

        #expect(history([run]).observations.isEmpty)
    }

    @Test("the distance track integrates speed and finds when a distance is reached")
    func distanceTrack() throws {
        let start = day(0)
        let samples = stride(from: 0.0, through: 100, by: 10).map {
            SpeedSample(time: start.addingTimeInterval($0), metersPerSecond: 3)
        }
        let track = DistanceTrack(speed: samples, gapThresholdSeconds: gap)

        #expect(abs(track.totalMeters - 300) < 1e-9)
        #expect(abs(track.meters(at: start.addingTimeInterval(25)) - 75) < 1e-9)
        let reached = try #require(track.time(reaching: 150))
        #expect(abs(reached.timeIntervalSince(start) - 50) < 1e-9)
        #expect(track.time(reaching: 301) == nil)
    }

    @Test("the median of an even count averages the middle two")
    func median() {
        #expect(HistoricalPaceEstimator.median([3, 1, 2]) == 2)
        #expect(HistoricalPaceEstimator.median([900, 1100]) == 1000)
        #expect(HistoricalPaceEstimator.median([]) == nil)
    }
}
