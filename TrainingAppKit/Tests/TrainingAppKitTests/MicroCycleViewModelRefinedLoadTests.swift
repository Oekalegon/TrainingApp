import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

/// A planned workout's expected load follows what the athlete's completed plans scored, on the cards, in
/// the stats and in the planned-workout sheets, as TrainingKit's own load series does.
@MainActor
@Suite("MicroCycleViewModel refined planned load", .serialized)
struct MicroCycleViewModelRefinedLoadTests {
    private struct StubImporter: ActivityImporting {
        let activities: [Activity]
        func importActivities(since anchor: ImportAnchor?) async throws -> ImportResult {
            ImportResult(upserted: activities, deletedSources: [], anchor: nil)
        }
    }

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    /// 20 minutes of a steady heart rate, a sample every 5 seconds. A hard run scores much more than
    /// the zone-2 plan says.
    private func run(on start: Date, bpm: Double, linkedTo planID: UUID?) -> Activity {
        let samples = stride(from: 0.0, through: 1200, by: 5).map {
            HeartRateSample(time: start.addingTimeInterval($0), bpm: bpm)
        }
        return Activity(
            source: .healthKit(UUID()), sport: .running, start: start, duration: 1200,
            heartRate: samples, scheduledPlanID: planID
        )
    }

    /// A twenty-minute zone-2 workout, planned once in the past (and done, hard) and once ahead.
    private struct Fixture {
        let viewModel: MicroCycleViewModel
        let model: TrainingModel
        let workout: StructuredWorkout
        let pastPlan: PlannedActivity
        let futurePlan: PlannedActivity
        let activity: Activity
        /// What the plan estimator alone says the workout scores.
        let baseLoad: Double
        /// What the completed run actually scored.
        let actualLoad: Double
    }

    private func makeFixture(
        bpm: Double = 165, wrappingActivityStore: ((InMemoryStore) -> any ActivityStore)? = nil
    ) async throws -> Fixture {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: wrappingActivityStore?(store) ?? store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        let athlete = AthleteProfile.fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 190)
        let model = TrainingModel(stores: stores, athlete: athlete)
        let workout = StructuredWorkout(
            name: "Easy", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1200), target: .heartRateZone(2))])]
        )
        try await model.add(workout, asOf: day(0))
        let pastPlan = PlannedActivity(workoutID: workout.id, date: day(-3))
        let futurePlan = PlannedActivity(workoutID: workout.id, date: day(5))
        try await model.add(pastPlan, asOf: day(0))
        try await model.add(futurePlan, asOf: day(0))
        try await model.load(in: day(-10)...day(10), asOf: day(0))
        try await model.importActivities(
            from: StubImporter(activities: [run(on: day(-3), bpm: bpm, linkedTo: pastPlan.id)]), asOf: day(0)
        )
        let viewModel = MicroCycleViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        let activity = try #require(model.activities.first)
        let baseLoad = TRIMPPlanEstimator().estimatedLoad(for: workout, athlete: model.athlete).value
        let actualLoad = viewModel.statisticsCalculator.summary(for: activity, athlete: model.athlete).load.value
        return Fixture(
            viewModel: viewModel, model: model, workout: workout, pastPlan: pastPlan, futurePlan: futurePlan,
            activity: activity, baseLoad: baseLoad, actualLoad: actualLoad
        )
    }

    @Test("a planned card shows the base estimate until the refinement is read, then what the run scored")
    func cardFollowsTheRefinement() async throws {
        let fixture = try await makeFixture()
        let viewModel = fixture.viewModel
        #expect(abs(fixture.actualLoad - fixture.baseLoad) > 5)

        // Cached before the refinement lands.
        #expect(abs((viewModel.plannedCardSummary(for: fixture.futurePlan).load ?? 0) - fixture.baseLoad) < 1e-6)

        await viewModel.refreshPlannedLoadIfNeeded(force: true)

        // Same workout and parameters: the median of one run is its actual load.
        #expect(abs((viewModel.plannedCardSummary(for: fixture.futurePlan).load ?? 0) - fixture.actualLoad) < 1e-6)
        #expect(viewModel.plannedLoadGeneration == 1)
    }

    @Test("a refresh that reads the same completed plans doesn't recompute anything")
    func unchangedRefreshKeepsTheGeneration() async throws {
        let fixture = try await makeFixture()
        await fixture.viewModel.refreshPlannedLoadIfNeeded(force: true)

        await fixture.viewModel.refreshPlannedLoadIfNeeded(force: true)

        #expect(fixture.viewModel.plannedLoadGeneration == 1)
    }

    @Test("with no completed plan there's nothing to refine, so the generation doesn't move")
    func nothingToRefine() async throws {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        let model = TrainingModel(stores: stores, athlete: .fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 190))
        let viewModel = MicroCycleViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        await viewModel.refreshPlannedLoadIfNeeded(force: true)

        #expect(viewModel.plannedLoadGeneration == 0)
        #expect(viewModel.refinedLoadEstimator == nil)
    }

    @Test("the activity's own card compares it with what was expected before it, not with itself")
    func linkedExpectationExcludesItsOwnRun() async throws {
        let fixture = try await makeFixture()
        await fixture.viewModel.refreshPlannedLoadIfNeeded(force: true)

        let expectation = try #require(fixture.viewModel.linkedPlanExpectation(for: fixture.activity))

        #expect(abs((expectation.load ?? 0) - fixture.baseLoad) < 1e-6)
    }

    @Test("a refresh after a new completed run moves the card, through the import path")
    func importRefreshesTheEstimate() async throws {
        let fixture = try await makeFixture()
        await fixture.viewModel.refreshWeekCachesIfNeeded(asOf: day(0), activitiesChanged: true)
        #expect(abs((fixture.viewModel.plannedCardSummary(for: fixture.futurePlan).load ?? 0) - fixture.actualLoad) < 1e-6)

        // Another run of the same workout, much easier: the median moves between the two.
        let easier = run(on: day(-1), bpm: 135, linkedTo: nil)
        let easierPlan = PlannedActivity(workoutID: fixture.workout.id, date: day(-1))
        try await fixture.model.add(easierPlan, asOf: day(0))
        try await fixture.model.importActivities(
            from: StubImporter(activities: [Activity(
                source: easier.source, sport: easier.sport, start: easier.start, duration: easier.duration,
                heartRate: easier.heartRate, scheduledPlanID: easierPlan.id
            )]),
            asOf: day(0)
        )
        await fixture.viewModel.refreshWeekCachesIfNeeded(asOf: day(0), activitiesChanged: true)

        let after = try #require(fixture.viewModel.plannedCardSummary(for: fixture.futurePlan).load)
        #expect(fixture.viewModel.plannedLoadGeneration == 2)
        #expect(after != fixture.actualLoad)
    }

    @Test("the plan's detail sheet agrees with its card")
    func detailSheetAgreesWithTheCard() async throws {
        let fixture = try await makeFixture()
        await fixture.viewModel.refreshPlannedLoadIfNeeded(force: true)

        let detail = fixture.viewModel.plannedWorkoutDetailViewModel(for: fixture.futurePlan, asOf: day(0))
        let card = fixture.viewModel.plannedCardSummary(for: fixture.futurePlan)

        #expect(abs((detail.summary.load ?? 0) - (card.load ?? -1)) < 1e-6)
    }

    @Test("the edit sheet opened from a plan's detail sheet expects the refined load")
    func editSheetUsesTheRefinement() async throws {
        let fixture = try await makeFixture()
        await fixture.viewModel.refreshPlannedLoadIfNeeded(force: true)

        let editor = fixture.viewModel.plannedWorkoutDetailViewModel(for: fixture.futurePlan, asOf: day(0)).makeEditor()

        #expect(abs((editor.expectedLoad?.value ?? 0) - fixture.actualLoad) < 1e-6)
    }

    @Test("the library and the planner it opens follow a refinement that lands after the tab was created")
    func libraryFollowsTheRefinement() async throws {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        let athlete = AthleteProfile.fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 190)
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = MicroCycleViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        // The tab is created first, as the app does, before any refinement exists.
        let library = viewModel.workoutLibraryViewModel()
        let template = BuiltInWorkoutTemplates.easyRun
        func expectedLoad() throws -> Double {
            try #require(library.entries(asOf: day(0)).first { $0.template.id == template.id }?.expectedLoad)
        }
        let before = try expectedLoad()

        let workout = try template.instantiate()
        try await model.add(workout, asOf: day(0))
        let plan = PlannedActivity(workoutID: workout.id, date: day(-3))
        try await model.add(plan, asOf: day(0))
        try await model.load(in: day(-10)...day(10), asOf: day(0))
        let seconds = WorkoutDurationEstimator().duration(for: workout, athlete: athlete)
        let samples = stride(from: 0.0, through: seconds, by: 5).map {
            HeartRateSample(time: day(-3).addingTimeInterval($0), bpm: 170)
        }
        try await model.importActivities(
            from: StubImporter(activities: [Activity(
                source: .healthKit(UUID()), sport: workout.sport, start: day(-3), duration: seconds,
                heartRate: samples, scheduledPlanID: plan.id
            )]),
            asOf: day(0)
        )
        await viewModel.refreshPlannedLoadIfNeeded(force: true)

        let after = try expectedLoad()
        #expect(after != before)
        #expect(abs((library.makePlanner(for: template, date: day(5)).expectedLoad?.value ?? 0) - after) < 1e-6)
    }

    @Test("a failed read keeps the refinement the cards already show")
    func failedReadKeepsThePreviousEstimator() async throws {
        var failing: FailingActivityStore?
        let fixture = try await makeFixture(wrappingActivityStore: {
            let wrapped = FailingActivityStore(base: $0)
            failing = wrapped
            return wrapped
        })
        let activityStore = try #require(failing)
        await fixture.viewModel.refreshPlannedLoadIfNeeded(force: true)
        #expect(fixture.viewModel.plannedLoadGeneration == 1)

        // The model keeps what it built until its next recompute, which is when reads would fail.
        await activityStore.setFailsIDReads(true)
        await fixture.model.recompute(asOf: day(0))
        await fixture.viewModel.refreshPlannedLoadIfNeeded(force: true)

        #expect(fixture.viewModel.plannedLoadKey == nil)
        #expect(fixture.viewModel.plannedLoadGeneration == 1)
        #expect(abs((fixture.viewModel.plannedCardSummary(for: fixture.futurePlan).load ?? 0) - fixture.actualLoad) < 1e-6)

        // The next refresh, once the store reads again, is not stuck on the failed key.
        await activityStore.setFailsIDReads(false)
        await fixture.viewModel.refreshPlannedLoadIfNeeded()
        #expect(abs((fixture.viewModel.plannedCardSummary(for: fixture.futurePlan).load ?? 0) - fixture.actualLoad) < 1e-6)
    }

    @Test("undoing the only completed plan is a real change: the cards go back to the base estimate")
    func lastCompletionRemovedApplies() async throws {
        let fixture = try await makeFixture()
        await fixture.viewModel.refreshPlannedLoadIfNeeded(force: true)
        #expect(fixture.viewModel.plannedLoadGeneration == 1)

        try await fixture.model.unlinkActivity(id: fixture.activity.id, asOf: day(0))
        await fixture.viewModel.refreshPlannedLoadIfNeeded(force: true)

        #expect(fixture.viewModel.plannedLoadGeneration == 2)
        #expect(fixture.viewModel.refinedLoadEstimator == nil)
        #expect(abs((fixture.viewModel.plannedCardSummary(for: fixture.futurePlan).load ?? 0) - fixture.baseLoad) < 1e-6)
    }

    @Test("a failed read, then the only completed plan undone, then a good read ends on the base figures once")
    func failureThenRealChange() async throws {
        var failing: FailingActivityStore?
        let fixture = try await makeFixture(wrappingActivityStore: {
            let wrapped = FailingActivityStore(base: $0)
            failing = wrapped
            return wrapped
        })
        let activityStore = try #require(failing)
        await fixture.viewModel.refreshPlannedLoadIfNeeded(force: true)
        #expect(fixture.viewModel.plannedLoadGeneration == 1)

        await activityStore.setFailsIDReads(true)
        await fixture.model.recompute(asOf: day(0))
        await fixture.viewModel.refreshPlannedLoadIfNeeded(force: true)
        #expect(fixture.viewModel.plannedLoadKey == nil)
        #expect(fixture.viewModel.plannedLoadGeneration == 1)

        // Reads recover, and the plan is undone: the next refresh isn't stuck on the failure and applies it.
        await activityStore.setFailsIDReads(false)
        try await fixture.model.unlinkActivity(id: fixture.activity.id, asOf: day(0))
        await fixture.viewModel.refreshPlannedLoadIfNeeded()

        #expect(fixture.viewModel.plannedLoadGeneration == 2)
        #expect(fixture.viewModel.refinedLoadEstimator == nil)
        #expect(abs((fixture.viewModel.plannedCardSummary(for: fixture.futurePlan).load ?? 0) - fixture.baseLoad) < 1e-6)
    }

    @Test("overlapping refreshes leave one consistent estimator")
    func overlappingRefreshes() async throws {
        let fixture = try await makeFixture()

        async let first: Void = fixture.viewModel.refreshPlannedLoadIfNeeded(force: true)
        async let second: Void = fixture.viewModel.refreshPlannedLoadIfNeeded(force: true)
        _ = await (first, second)

        #expect(fixture.viewModel.plannedLoadGeneration == 1)
        #expect(abs((fixture.viewModel.plannedCardSummary(for: fixture.futurePlan).load ?? 0) - fixture.actualLoad) < 1e-6)
    }

    @Test("editing a completed plan's workout in place refreshes the references without a force")
    func workoutEditRefreshes() async throws {
        let fixture = try await makeFixture()
        await fixture.viewModel.refreshPlannedLoadIfNeeded(force: true)
        #expect(fixture.viewModel.plannedLoadGeneration == 1)

        // Same id and count, a step a minute longer: still within the comparable-duration check.
        var edited = fixture.workout
        edited.blocks = [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1260), target: .heartRateZone(2))])]
        try await fixture.model.add(edited, asOf: day(0))
        await fixture.viewModel.refreshPlannedLoadIfNeeded()

        #expect(fixture.viewModel.plannedLoadGeneration == 2)
    }
}
