import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

/// Which shown values count as estimates and get a "~" (MVP2-8): planned loads the athlete didn't
/// set, durations and distances forecast from the athlete's paces, loads scored from perceived
/// effort, and projected days' fitness figures. Measured values and a plan's targets don't.
@MainActor
@Suite("Estimated values (MVP2-8)")
struct EstimatedValuesTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func makeViewModel(today: Int = 2) -> (WeekViewModel, TrainingModel, InMemoryStore) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        let athlete = AthleteProfile.fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 190)
        let model = TrainingModel(stores: stores, athlete: athlete)
        return (WeekViewModel(model: model, refresher: FakeRefresher(), today: day(today)), model, store)
    }

    private func workout(_ goals: [StepGoal], repetitions: Int = 1) -> StructuredWorkout {
        StructuredWorkout(
            name: "Run", sport: .running,
            blocks: [WorkoutBlock(
                steps: goals.map { WorkoutStep(kind: .work, goal: $0, target: .heartRateZone(2)) },
                repetitions: repetitions
            )]
        )
    }

    /// 20 minutes of a steady 140 bpm, a sample every 5 seconds: scored by heart-rate TRIMP.
    private func heartRateActivity(on start: Date) -> Activity {
        let samples = stride(from: 0.0, through: 1200, by: 5).map {
            HeartRateSample(time: start.addingTimeInterval($0), bpm: 140)
        }
        return Activity(source: .healthKit(UUID()), sport: .running, start: start, duration: 1200, heartRate: samples)
    }

    /// No heart rate, only perceived effort: scored by duration × RPE.
    private func effortActivity(on start: Date) -> Activity {
        Activity(source: .manual, sport: .running, start: start, duration: 1800, distanceMeters: 5000, perceivedExertion: 5)
    }

    // MARK: - Marker

    @Test("the marker goes in front of an estimate only, and VoiceOver says \"estimated\" instead")
    func marker() {
        #expect(EstimateMarker.text("65", isEstimated: true) == "~65")
        #expect(EstimateMarker.text("65", isEstimated: false) == "65")
        #expect(EstimateMarker.spoken("65", isEstimated: true) == "estimated 65")
        #expect(EstimateMarker.spoken("65", isEstimated: false) == "65")
        #expect(EstimateMarker.spokenForm(of: "~8.2 km") == "estimated 8.2 km")
        #expect(EstimateMarker.spokenForm(of: "8.2 km") == "8.2 km")
    }

    // MARK: - Sources

    @Test("heart-rate TRIMP and a manual load are not estimates; plan and perceived-effort loads are")
    func loadMethods() {
        #expect(!LoadMethod.exponentialTRIMP.isEstimate)
        #expect(!LoadMethod.manual.isEstimate)
        #expect(LoadMethod.estimatedFromPlan.isEstimate)
        #expect(LoadMethod.durationRPE.isEstimate)
    }

    @Test("a workout sets its duration only with time steps, and its distance only with distance steps")
    func workoutForecasts() {
        let timed = workout([.time(1200)])
        #expect(!timed.isDurationForecast)
        #expect(timed.isDistanceForecast)

        let distance = workout([.distance(5000)])
        #expect(distance.isDurationForecast)
        #expect(!distance.isDistanceForecast)

        let open = workout([.open])
        #expect(open.isDurationForecast)
        #expect(open.isDistanceForecast)

        let mixed = workout([.time(600), .distance(1000)])
        #expect(mixed.isDurationForecast)
        #expect(mixed.isDistanceForecast)

        // A block repeated zero times isn't run, so its distance step doesn't make the duration a forecast.
        let skipped = StructuredWorkout(
            name: "Run", sport: .running,
            blocks: [
                WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1200), target: .heartRateZone(2))]),
                WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .distance(1000), target: .heartRateZone(2))], repetitions: 0),
            ]
        )
        #expect(!skipped.isDurationForecast)
    }

    @Test("a plan's load is an estimate unless the athlete set it")
    func planLoad() {
        #expect(PlannedActivity(workoutID: UUID(), date: day(2)).isExpectedLoadEstimated)
        #expect(!PlannedActivity(workoutID: UUID(), date: day(2), expectedLoadOverride: 60).isExpectedLoadEstimated)
    }

    @Test("Form is projected when the previous day is, not when its own day is")
    func formFollowsPreviousDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func metrics(_ offset: Int, projected: Bool) -> FitnessMetrics {
            FitnessMetrics(
                day: day(offset), load: 0, ctl: 0, atl: 0, tsb: 0,
                monotony: .nan, strain: .nan, isProjected: projected, isWarmingUp: false
            )
        }
        let series = [metrics(0, projected: false), metrics(1, projected: true), metrics(2, projected: true)]

        #expect(!FitnessMetrics.isFormProjected(on: day(0), in: series, calendar: calendar))
        // Day 1 is projected, but its Form comes from day 0, which isn't.
        #expect(!FitnessMetrics.isFormProjected(on: day(1), in: series, calendar: calendar))
        #expect(FitnessMetrics.isFormProjected(on: day(2), in: series, calendar: calendar))
    }

    // MARK: - Cards

    @Test("a planned card marks the estimator's load and a forecast duration, not a target")
    func plannedCardSummary() async throws {
        let (viewModel, model, _) = makeViewModel()
        func summary(_ workout: StructuredWorkout, override: Double? = nil) async throws -> WeekViewModel.PlannedCardSummary {
            try await model.add(workout, asOf: day(2))
            let plan = PlannedActivity(workoutID: workout.id, date: day(3), expectedLoadOverride: override)
            try await model.add(plan, asOf: day(2))
            return viewModel.plannedCardSummary(for: plan)
        }

        let timed = try await summary(workout([.time(1200)]))
        #expect(timed.isLoadEstimated)
        #expect(!timed.isExtentEstimated)

        let distance = try await summary(workout([.distance(5000)]))
        guard case .distance? = distance.extent else {
            Issue.record("expected a distance extent")
            return
        }
        #expect(!distance.isExtentEstimated)

        let mixed = try await summary(workout([.time(600), .distance(1000)]))
        #expect(mixed.isExtentEstimated)

        let overridden = try await summary(workout([.time(1200)]), override: 60)
        #expect(!overridden.isLoadEstimated)

        let orphan = viewModel.plannedCardSummary(for: PlannedActivity(workoutID: UUID(), date: day(3)))
        #expect(!orphan.isLoadEstimated)
        #expect(!orphan.isExtentEstimated)
    }

    @Test("a linked card marks the plan's forecast figure and estimated load, not its targets")
    func linkedPlanExpectation() async throws {
        let (viewModel, model, _) = makeViewModel()
        let timed = workout([.time(1200)])
        let distance = workout([.distance(5000)])
        try await model.add(timed, asOf: day(2))
        try await model.add(distance, asOf: day(2))
        let timedPlan = PlannedActivity(workoutID: timed.id, date: day(2))
        let distancePlan = PlannedActivity(workoutID: distance.id, date: day(2), expectedLoadOverride: 60)
        try await model.add(timedPlan, asOf: day(2))
        try await model.add(distancePlan, asOf: day(2))
        func activity(linkedTo plan: PlannedActivity) -> Activity {
            var activity = heartRateActivity(on: day(2))
            activity.linkedPlanID = plan.id
            return activity
        }

        let fromTime = try #require(viewModel.linkedPlanExpectation(for: activity(linkedTo: timedPlan)))
        #expect(fromTime.isLoadEstimated)
        #expect(!fromTime.isDurationEstimated)
        #expect(fromTime.isDistanceEstimated)

        let fromDistance = try #require(viewModel.linkedPlanExpectation(for: activity(linkedTo: distancePlan)))
        #expect(!fromDistance.isLoadEstimated)
        #expect(fromDistance.isDurationEstimated)
        #expect(!fromDistance.isDistanceEstimated)
    }

    @Test("an activity's card marks a load scored from perceived effort, not one from heart rate")
    func activityCardLoad() throws {
        let (viewModel, _, _) = makeViewModel()

        let measured = viewModel.activityCardContent(for: heartRateActivity(on: day(2)))
        #expect(measured.trainingLoad != nil)
        #expect(!measured.isTrainingLoadEstimated)

        let effort = viewModel.activityCardContent(for: effortActivity(on: day(2)))
        #expect(effort.trainingLoad != nil)
        #expect(effort.isTrainingLoadEstimated)
    }

    // MARK: - Stats bar

    @Test("the stats bar marks an expected total that includes an estimate, and only that total")
    func statsBarExpectedTotals() async throws {
        let (viewModel, _, store) = makeViewModel()
        let today = viewModel.displayedWeekStart
        let timed = workout([.time(1200)])
        try await store.upsert([timed])
        try await store.upsert([PlannedActivity(workoutID: timed.id, date: today.addingTimeInterval(86400))])
        await viewModel.load(asOf: today)

        let page = try #require(viewModel.sportStatsPages(asOf: today).first { $0.sport == .running })

        #expect(!page.isLoadEstimated)
        #expect(page.isExpectedLoadEstimated)
        #expect(!page.isExpectedTimeEstimated)
        #expect(page.isExpectedDistanceEstimated)
    }

    @Test("the stats bar's load is marked when an activity was scored from perceived effort; a set plan load isn't")
    func statsBarEffortLoad() async throws {
        let (viewModel, _, store) = makeViewModel()
        let today = viewModel.displayedWeekStart
        let distance = workout([.distance(5000)])
        try await store.upsert([effortActivity(on: today)])
        try await store.upsert([distance])
        try await store.upsert([
            PlannedActivity(workoutID: distance.id, date: today.addingTimeInterval(86400), expectedLoadOverride: 60)
        ])
        await viewModel.load(asOf: today)

        let page = try #require(viewModel.sportStatsPages(asOf: today).first { $0.sport == .running })

        #expect(page.isLoadEstimated)
        #expect(page.isExpectedLoadEstimated)
        #expect(page.isExpectedTimeEstimated)
        #expect(!page.isExpectedDistanceEstimated)
    }

    @Test("a week whose plans all have a set load and nothing scored from effort shows its expected load plainly")
    func statsBarTargetLoad() async throws {
        let (viewModel, _, store) = makeViewModel()
        let today = viewModel.displayedWeekStart
        let timed = workout([.time(1200)])
        try await store.upsert([timed])
        try await store.upsert([
            PlannedActivity(workoutID: timed.id, date: today.addingTimeInterval(86400), expectedLoadOverride: 60)
        ])
        await viewModel.load(asOf: today)

        let page = try #require(viewModel.sportStatsPages(asOf: today).first { $0.sport == .running })

        #expect(!page.isExpectedLoadEstimated)
    }
}
