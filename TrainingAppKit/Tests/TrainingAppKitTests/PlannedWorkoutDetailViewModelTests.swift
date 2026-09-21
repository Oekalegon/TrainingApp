import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@MainActor
@Suite("PlannedWorkoutDetailViewModel")
struct PlannedWorkoutDetailViewModelTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func makeModel() async throws -> TrainingModel {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, athleteStore: store
        )
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC", restingHeartRateBPM: 50, maxHeartRateBPM: 190)
        try await store.save(athlete)
        let model = TrainingModel(stores: stores, athlete: athlete)
        try await model.load(in: day(-7)...day(14), asOf: day(0))
        return model
    }

    private func intervalWorkout() -> StructuredWorkout {
        var workout = StructuredWorkout(
            name: "Intervals", sport: .running,
            blocks: [
                WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(600), target: .heartRateZone(1))]),
                WorkoutBlock(
                    steps: [
                        WorkoutStep(kind: .work, goal: .time(480), target: .heartRateZone(4)),
                        WorkoutStep(kind: .recovery, goal: .distance(400), target: .heartRateZone(1)),
                    ],
                    repetitions: 4
                ),
                WorkoutBlock(steps: [WorkoutStep(kind: .cooldown, goal: .open)]),
            ]
        )
        workout.workoutKitID = UUID()
        return workout
    }

    @Test("stepLines shows one line per block, with a repetition prefix and each step's goal")
    func stepLinesDescribeBlocks() async throws {
        let model = try await makeModel()
        let workout = intervalWorkout()
        try await model.add(workout)
        let plan = PlannedActivity(workoutID: workout.id, date: day(3))
        try await model.add(plan)

        let viewModel = PlannedWorkoutDetailViewModel(model: model, plan: plan, scheduler: nil)

        // Distances follow the device's units (metric locally, imperial on a US CI runner), so the
        // expectation is built with the same formatter rather than hard-coding "400 m".
        let recoveryDistance = Measurement(value: 400, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated))
        #expect(viewModel.stepLines == [
            "Warm-up 10:00",
            "4 × Work 8:00, Recovery \(recoveryDistance)",
            "Cool-down open",
        ])
    }

    @Test("a duration-based workout shows an estimated distance too, from the athlete's pace model")
    func durationBasedWorkoutShowsProjectedDistance() async throws {
        let model = try await makeModel()
        let workout = intervalWorkout()
        try await model.add(workout)
        let plan = PlannedActivity(workoutID: workout.id, date: day(3))
        try await model.add(plan)

        let viewModel = PlannedWorkoutDetailViewModel(model: model, plan: plan, scheduler: nil)

        #expect((viewModel.expectedDuration ?? 0) > 0)
        #expect((viewModel.expectedDistanceMeters ?? 0) > 0)
        #expect(viewModel.isDistanceForecast)
        #expect(viewModel.summary.name == "Intervals")
    }

    @Test("a distance-only workout shows its distance")
    func distanceOnlyWorkoutShowsDistance() async throws {
        let model = try await makeModel()
        let workout = StructuredWorkout(
            name: "Reps", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .distance(400), target: .heartRateZone(4))], repetitions: 5)]
        )
        try await model.add(workout)
        let plan = PlannedActivity(workoutID: workout.id, date: day(3))
        try await model.add(plan)

        let viewModel = PlannedWorkoutDetailViewModel(model: model, plan: plan, scheduler: nil)

        #expect(viewModel.expectedDistanceMeters == 2000)
        // Defined by the workout's own steps, so not a forecast.
        #expect(!viewModel.isDistanceForecast)
    }

    @Test("deletionMessage names the workout and the plan's day in the athlete's timezone")
    func deletionMessageNamesWorkoutAndDay() async throws {
        let model = try await makeModel()
        let workout = intervalWorkout()
        try await model.add(workout)
        let plan = PlannedActivity(workoutID: workout.id, date: day(3))
        try await model.add(plan)

        let viewModel = PlannedWorkoutDetailViewModel(model: model, plan: plan, scheduler: nil)

        #expect(viewModel.deletionMessage.hasPrefix("Intervals on "))
    }

    @Test("delete() removes the plan but keeps its workout, and removes its WorkoutKit entry")
    func deleteRemovesPlanKeepsWorkout() async throws {
        let model = try await makeModel()
        let workout = intervalWorkout()
        try await model.add(workout)
        let plan = PlannedActivity(workoutID: workout.id, date: day(3))
        let other = PlannedActivity(workoutID: workout.id, date: day(4))
        try await model.add(plan)
        try await model.add(other)
        let scheduler = FakeScheduler()
        let viewModel = PlannedWorkoutDetailViewModel(model: model, plan: plan, scheduler: scheduler)
        #expect(!viewModel.isDeleted)

        let didDelete = await viewModel.delete()

        #expect(didDelete)
        #expect(viewModel.isDeleted)
        #expect(model.plans.map(\.id) == [other.id])
        #expect(model.workouts.map(\.id) == [workout.id])
        #expect(await scheduler.unscheduledPlans.map(\.id) == [plan.id])
        #expect(viewModel.deleteError == nil)
    }

    @Test("delete() works for a plan whose workout left the library, with no WorkoutKit call")
    func deleteOrphanedPlan() async throws {
        let model = try await makeModel()
        let orphan = PlannedActivity(workoutID: UUID(), date: day(3))
        try await model.add(orphan)
        let scheduler = FakeScheduler()
        let viewModel = PlannedWorkoutDetailViewModel(model: model, plan: orphan, scheduler: scheduler)

        #expect(await viewModel.delete())

        #expect(model.plans.isEmpty)
        #expect(await scheduler.callLog.isEmpty)
    }

    @Test("the summary follows an edit saved through makeEditor()")
    func summaryFollowsEdit() async throws {
        let model = try await makeModel()
        let workout = intervalWorkout()
        try await model.add(workout)
        let plan = PlannedActivity(workoutID: workout.id, date: day(3))
        try await model.add(plan)
        let viewModel = PlannedWorkoutDetailViewModel(model: model, plan: plan, scheduler: nil)

        let editor = viewModel.makeEditor()
        editor.loadOverride = 90
        #expect(await editor.save())

        #expect(viewModel.plan.expectedLoadOverride == 90)
        #expect(viewModel.summary.load == 90)
    }
}
