import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@MainActor
@Suite("WeekViewModel intensity (MVP2-43)")
struct WeekViewModelIntensityTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func makeViewModel() -> (WeekViewModel, TrainingModel) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, athleteStore: store
        )
        let athlete = AthleteProfile.fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 190)
        let model = TrainingModel(stores: stores, athlete: athlete)
        return (WeekViewModel(model: model, refresher: FakeRefresher(), today: day(2)), model)
    }

    /// A 20 minute single-step running workout at the given heart-rate zone.
    private func workout(id: UUID = UUID(), zone: Int) -> StructuredWorkout {
        StructuredWorkout(
            id: id, name: "Run", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1200), target: .heartRateZone(zone))])]
        )
    }

    /// 20 minutes of a steady heart rate, a sample every 5 seconds.
    private func steadyActivity(bpm: Double) -> Activity {
        let start = day(2)
        let samples = stride(from: 0.0, through: 1200, by: 5).map {
            HeartRateSample(time: start.addingTimeInterval($0), bpm: bpm)
        }
        return Activity(source: .healthKit(UUID()), sport: .running, start: start, duration: 1200, heartRate: samples)
    }

    @Test("a planned workout's intensity comes from its steps and is labelled planned")
    func planIntensity() async throws {
        let (viewModel, model) = makeViewModel()
        let hard = workout(zone: 4)
        try await model.add(hard, asOf: day(2))
        let plan = PlannedActivity(workoutID: hard.id, date: day(2))
        try await model.add(plan, asOf: day(2))

        let result = try #require(viewModel.intensity(for: plan))

        #expect(result.category == .high)
        #expect(result.source == .planned)
    }

    @Test("a plan whose workout isn't loaded has no intensity")
    func planWithoutWorkout() {
        let (viewModel, _) = makeViewModel()

        #expect(viewModel.intensity(for: PlannedActivity(workoutID: UUID(), date: day(2))) == nil)
    }

    @Test("an unlinked activity's intensity comes from its heart rate and is labelled measured")
    func activityIntensity() throws {
        let (viewModel, _) = makeViewModel()

        // 140 bpm is zone 2 for a 50/190 athlete.
        let result = try #require(viewModel.intensity(for: steadyActivity(bpm: 140)))

        #expect(result.category == .low)
        #expect(result.source == .measured)
    }

    @Test("editing a workout in place refreshes its plan's intensity, though no count changed")
    func editedWorkoutRefreshesPlanIntensity() async throws {
        let (viewModel, model) = makeViewModel()
        let id = UUID()
        try await model.add(workout(id: id, zone: 4), asOf: day(2))
        let plan = PlannedActivity(workoutID: id, date: day(2))
        try await model.add(plan, asOf: day(2))
        #expect(viewModel.intensity(for: plan)?.category == .high)

        try await model.add(workout(id: id, zone: 2), asOf: day(2))

        #expect(model.workouts.count == 1)
        #expect(viewModel.intensity(for: plan)?.category == .low)
    }

    @Test("changing the classifier thresholds refreshes cached intensities")
    func changedParametersRefresh() async throws {
        let (viewModel, model) = makeViewModel()
        let hard = workout(zone: 4)
        try await model.add(hard, asOf: day(2))
        let plan = PlannedActivity(workoutID: hard.id, date: day(2))
        try await model.add(plan, asOf: day(2))
        #expect(viewModel.intensity(for: plan)?.category == .high)

        model.intensityParameters = IntensityClassifierParameters(highMinimumSeconds: 7200)

        // 20 minutes of zone 4 can no longer reach high; it still counts as medium.
        #expect(viewModel.intensity(for: plan)?.category == .medium)
    }

    @Test("intensity display names and VoiceOver text")
    func displayText() {
        let firm = IntensityAssessment(category: .high, source: .planned, confidence: .high, hardSeconds: 0, moderateSeconds: 0)

        #expect(firm.accessibilityDescription == "Intensity: high, planned")
        #expect(IntensityCategory.veryLow.displayName == "Very low")
    }

    // MARK: - Linked plan expectations (planned values on an activity's card)

    @Test("a duration workout expects its duration plus a distance projected from pace, and a distance workout the reverse")
    func linkedExpectationHasBothValues() async throws {
        let (viewModel, model) = makeViewModel()
        let timed = workout(zone: 2)   // 20 minutes at zone 2
        let distance = StructuredWorkout(
            name: "5 km", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .distance(5000), target: .heartRateZone(2))])]
        )
        try await model.add(timed, asOf: day(2))
        try await model.add(distance, asOf: day(2))
        let timedPlan = PlannedActivity(workoutID: timed.id, date: day(2))
        let distancePlan = PlannedActivity(workoutID: distance.id, date: day(2))
        try await model.add(timedPlan, asOf: day(2))
        try await model.add(distancePlan, asOf: day(2))

        func activity(linkedTo plan: PlannedActivity) -> Activity {
            var activity = steadyActivity(bpm: 140)
            activity.linkedPlanID = plan.id
            return activity
        }

        // The fixture's threshold pace is 300 s/km; zone 2 is 1.20 × that, 360 s/km.
        let fromTime = try #require(viewModel.linkedPlanExpectation(for: activity(linkedTo: timedPlan)))
        #expect(fromTime.duration == 1200)
        #expect(abs((fromTime.distanceMeters ?? 0) - 1200 / 0.36) < 0.5)

        let fromDistance = try #require(viewModel.linkedPlanExpectation(for: activity(linkedTo: distancePlan)))
        #expect(fromDistance.distanceMeters == 5000)
        #expect(abs((fromDistance.duration ?? 0) - 1800) < 0.5)
    }

    // MARK: - Card cache invalidation

    private func linked(_ activity: Activity, to plan: PlannedActivity) -> Activity {
        var activity = activity
        activity.linkedPlanID = plan.id
        return activity
    }

    @Test("editing a plan's load override refreshes the card summary and the linked activity's expectation, though no count changed")
    func overrideEditRefreshesLoad() async throws {
        let (viewModel, model) = makeViewModel()
        let easy = workout(zone: 2)
        try await model.add(easy, asOf: day(2))
        var plan = PlannedActivity(workoutID: easy.id, date: day(2), expectedLoadOverride: 50)
        try await model.add(plan, asOf: day(2))
        let activity = linked(steadyActivity(bpm: 140), to: plan)
        #expect(viewModel.linkedPlanExpectation(for: activity)?.load == 50)
        #expect(viewModel.plannedCardSummary(for: plan).load == 50)

        plan.expectedLoadOverride = 80
        try await model.add(plan, asOf: day(2))

        #expect(model.plans.count == 1)
        #expect(viewModel.linkedPlanExpectation(for: activity)?.load == 80)
        #expect(viewModel.plannedCardSummary(for: plan).load == 80)
    }

    @Test("changing the athlete's pace model refreshes the projected distance")
    func paceChangeRefreshesProjection() async throws {
        let (viewModel, model) = makeViewModel()
        let easy = workout(zone: 2)   // 20 minutes at zone 2
        try await model.add(easy, asOf: day(2))
        let plan = PlannedActivity(workoutID: easy.id, date: day(2))
        try await model.add(plan, asOf: day(2))
        let activity = linked(steadyActivity(bpm: 140), to: plan)
        // Threshold pace 300 s/km, zone 2 is 1.20 × that: 360 s/km.
        #expect(abs((viewModel.linkedPlanExpectation(for: activity)?.distanceMeters ?? 0) - 1200 / 0.36) < 0.5)

        var athlete = model.athlete
        athlete.paceModel = PaceModel(thresholdPaceSecondsPerKilometer: 240)
        model.athlete = athlete

        // Now 288 s/km.
        #expect(abs((viewModel.linkedPlanExpectation(for: activity)?.distanceMeters ?? 0) - 1200 / 0.288) < 0.5)
    }

    @Test("linking and unlinking an activity to a plan refreshes its intensity")
    func relinkingRefreshesIntensity() async throws {
        let (viewModel, model) = makeViewModel()
        let easy = workout(zone: 2)
        try await model.add(easy, asOf: day(2))
        let plan = PlannedActivity(workoutID: easy.id, date: day(2))
        try await model.add(plan, asOf: day(2))
        // 20 minutes at 170 bpm (zone 4): by heart rate alone a hard session.
        let hardRun = steadyActivity(bpm: 170)

        #expect(viewModel.intensity(for: hardRun)?.category == .high)

        // Against an easy plan, heart rate can raise the result by one level only.
        let linkedRun = linked(hardRun, to: plan)
        #expect(viewModel.intensity(for: linkedRun)?.category == .medium)
        #expect(viewModel.intensity(for: linkedRun)?.source == .blended)

        // Same activity id, unlinked again.
        #expect(viewModel.intensity(for: hardRun)?.category == .high)
    }

    @Test("entries for deleted plans are pruned")
    func deletedPlansArePruned() async throws {
        let (viewModel, model) = makeViewModel()
        let easy = workout(zone: 2)
        try await model.add(easy, asOf: day(2))
        let first = PlannedActivity(workoutID: easy.id, date: day(2))
        let second = PlannedActivity(workoutID: easy.id, date: day(3))
        try await model.add(first, asOf: day(2))
        try await model.add(second, asOf: day(2))
        _ = viewModel.intensity(for: first)
        _ = viewModel.intensity(for: second)
        #expect(viewModel.planIntensityCache.count == 2)

        try await model.deletePlan(id: first.id, asOf: day(2))
        _ = viewModel.intensity(for: second)

        #expect(viewModel.planIntensityCache.count == 1)
    }

    // MARK: - Card content

    @Test("a plan on a past day with no completed activity is missed; today's, a future one, and a completed one are not")
    func missedPlans() async throws {
        let (viewModel, _) = makeViewModel()
        let workoutID = UUID()
        let past = PlannedActivity(workoutID: workoutID, date: day(0))
        let today = PlannedActivity(workoutID: workoutID, date: day(2))
        let future = PlannedActivity(workoutID: workoutID, date: day(4))
        let completed = PlannedActivity(workoutID: workoutID, date: day(0), completedActivityID: UUID())

        #expect(viewModel.plannedCardContent(for: past, asOf: day(2)).isMissed)
        #expect(!viewModel.plannedCardContent(for: today, asOf: day(2)).isMissed)
        #expect(!viewModel.plannedCardContent(for: future, asOf: day(2)).isMissed)
        #expect(!viewModel.plannedCardContent(for: completed, asOf: day(2)).isMissed)
    }

    @Test("a linked activity's card content bundles its intensity and the plan's expectation")
    func activityCardContentBundlesEverything() async throws {
        let (viewModel, model) = makeViewModel()
        let easy = workout(zone: 2)
        try await model.add(easy, asOf: day(2))
        let plan = PlannedActivity(workoutID: easy.id, date: day(2))
        try await model.add(plan, asOf: day(2))
        let activity = linked(steadyActivity(bpm: 140), to: plan)

        let content = viewModel.activityCardContent(for: activity)

        #expect(content.intensity?.category == .low)
        #expect(content.planned?.duration == 1200)
        #expect(content.trainingLoad != nil)
        #expect(viewModel.activityCardContent(for: steadyActivity(bpm: 140)).planned == nil)
    }
}
