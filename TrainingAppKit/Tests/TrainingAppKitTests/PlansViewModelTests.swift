import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@MainActor
@Suite("PlansViewModel (MVP5-125)")
struct PlansViewModelTests {
    private let today = Date(timeIntervalSince1970: 1_700_000_000)

    private func day(_ offset: Int) -> Date {
        today.addingTimeInterval(Double(offset) * 86400)
    }

    private func makeModel() async throws -> (InMemoryStore, TrainingModel) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store, trainingPlanStore: store
        )
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC", restingHeartRateBPM: 50, maxHeartRateBPM: 190)
        try await store.save(athlete)
        let model = TrainingModel(stores: stores, athlete: athlete)
        try await model.load(in: day(-30)...day(60), asOf: today)
        return (store, model)
    }

    private func makeViewModel(_ model: TrainingModel) -> PlansViewModel {
        let today = self.today
        return PlansViewModel(model: model, now: { today })
    }

    private func workout() -> StructuredWorkout {
        StructuredWorkout(
            name: "Steady", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(3600), target: .heartRateZone(2))])]
        )
    }

    /// A plan with `count` daily workouts starting `offset` days from today.
    @discardableResult
    private func addPlan(
        _ name: String, status: PlanStatus, workouts count: Int, from offset: Int = 1,
        to model: TrainingModel, store: InMemoryStore
    ) async throws -> TrainingPlan {
        let plan = try await model.createTrainingPlan(named: name, status: status, asOf: today)
        let steady = workout()
        try await store.upsert([steady])
        let items = (0..<count).map { PlannedActivity(workoutID: steady.id, date: day(offset + $0), planID: plan.id) }
        try await store.upsert(items)
        try await model.load(in: day(-30)...day(60), asOf: today)
        return plan
    }

    @Test("lists the active plan first, then drafts, then archived ones, with workout counts")
    func listsPlansByStatus() async throws {
        let (store, model) = try await makeModel()
        try await addPlan("Old", status: .archived, workouts: 1, to: model, store: store)
        try await addPlan("Draft", status: .draft, workouts: 2, to: model, store: store)
        try await addPlan("Live", status: .active, workouts: 3, to: model, store: store)
        let viewModel = makeViewModel(model)

        await viewModel.reload()

        #expect(viewModel.entries.map(\.plan.name) == ["Live", "Draft", "Old"])
        #expect(viewModel.entries.map(\.workoutCount) == [3, 2, 1])
        #expect(viewModel.entries.first?.isActive == true)
        #expect(viewModel.entries[0].dateSpan == day(1)...day(3))
        #expect(viewModel.loadError == nil)
    }

    @Test("activating a draft makes it the only active plan and swaps what the model counts")
    func activateSwapsActivePlan() async throws {
        let (store, model) = try await makeModel()
        let live = try await addPlan("Live", status: .active, workouts: 3, to: model, store: store)
        let draft = try await addPlan("Draft", status: .draft, workouts: 2, to: model, store: store)
        let viewModel = makeViewModel(model)
        var notified = 0
        viewModel.onPlansChanged = { notified += 1 }
        await viewModel.reload()
        #expect(model.plans.count == 3)

        await viewModel.activate(try #require(viewModel.entry(id: draft.id)))

        #expect(viewModel.entries.filter(\.isActive).map(\.id) == [draft.id])
        #expect(viewModel.entry(id: live.id)?.plan.status == .draft)
        #expect(Set(model.plans.compactMap(\.planID)) == [draft.id])
        #expect(notified == 1)
        #expect(viewModel.actionError == nil)
    }

    @Test("archiving the active plan leaves none active and nothing in the model")
    func archiveActive() async throws {
        let (store, model) = try await makeModel()
        let live = try await addPlan("Live", status: .active, workouts: 3, to: model, store: store)
        let viewModel = makeViewModel(model)
        await viewModel.reload()

        await viewModel.archive(try #require(viewModel.entry(id: live.id)))

        #expect(viewModel.entry(id: live.id)?.plan.status == .archived)
        #expect(viewModel.entries.contains { $0.isActive } == false)
        #expect(model.plans.isEmpty)
    }

    @Test("duplicating makes a draft copy with the plan's workouts and leaves the original")
    func duplicate() async throws {
        let (store, model) = try await makeModel()
        let live = try await addPlan("Live", status: .active, workouts: 3, to: model, store: store)
        let viewModel = makeViewModel(model)
        await viewModel.reload()

        let copy = await viewModel.duplicate(try #require(viewModel.entry(id: live.id)))

        let copyEntry = try #require(copy.flatMap { viewModel.entry(id: $0.id) })
        #expect(copyEntry.plan.status == .draft)
        #expect(copyEntry.plan.name == "Live copy")
        #expect(copyEntry.workoutCount == 3)
        #expect(viewModel.entry(id: live.id)?.workoutCount == 3)
        #expect(model.plans.count == 3)
    }

    @Test("renaming trims the name; an empty name is refused")
    func rename() async throws {
        let (store, model) = try await makeModel()
        let draft = try await addPlan("Draft", status: .draft, workouts: 1, to: model, store: store)
        let viewModel = makeViewModel(model)
        await viewModel.reload()
        let entry = try #require(viewModel.entry(id: draft.id))

        await viewModel.rename(entry, to: "   ")
        #expect(viewModel.actionError != nil)
        #expect(viewModel.entry(id: draft.id)?.plan.name == "Draft")

        viewModel.actionError = nil
        await viewModel.rename(entry, to: "  Marathon  ")
        #expect(viewModel.entry(id: draft.id)?.plan.name == "Marathon")
        #expect(viewModel.actionError == nil)
    }

    @Test("deleting removes a plan with its workouts; a plan with a completed workout is refused")
    func delete() async throws {
        let (store, model) = try await makeModel()
        let draft = try await addPlan("Draft", status: .draft, workouts: 2, to: model, store: store)
        let done = try await addPlan("Done", status: .archived, workouts: 1, to: model, store: store)
        var completed = try #require(try await store.plans(in: day(-30)...day(60)).first { $0.planID == done.id })
        completed.completedActivityID = UUID()
        try await store.upsert([completed])
        let viewModel = makeViewModel(model)
        await viewModel.reload()
        #expect(viewModel.entry(id: done.id)?.canDelete == false)

        await viewModel.delete(try #require(viewModel.entry(id: done.id)))
        #expect(viewModel.entry(id: done.id) != nil)
        #expect(viewModel.actionError?.contains("Archive it instead") == true)

        viewModel.actionError = nil
        await viewModel.delete(try #require(viewModel.entry(id: draft.id)))
        #expect(viewModel.entry(id: draft.id) == nil)
        #expect(try await store.plans(in: day(-30)...day(60)).contains { $0.planID == draft.id } == false)
        #expect(viewModel.actionError == nil)
    }

    @Test("without a plan store the screen is unavailable and changes report a failure")
    func withoutPlanStore() async throws {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        let model = TrainingModel(stores: stores, athlete: AthleteProfile.fixture(timeZoneIdentifier: "UTC"))
        let viewModel = makeViewModel(model)
        #expect(viewModel.isAvailable == false)

        await viewModel.rename(
            PlansViewModel.Entry(
                plan: TrainingPlan(name: "x"), workoutCount: 0, dateSpan: nil, hasCompletedWorkouts: false
            ),
            to: "y"
        )
        #expect(viewModel.actionError != nil)
    }

    @Test("a preview projects the draft beside the active plan without touching the model's plans")
    func previewProjectsDraftAgainstActive() async throws {
        let (store, model) = try await makeModel()
        try await addPlan("Live", status: .active, workouts: 3, to: model, store: store)
        let draft = try await addPlan("Draft", status: .draft, workouts: 10, from: 1, to: model, store: store)
        let viewModel = makeViewModel(model)
        await viewModel.reload()
        let plansBefore = model.plans

        await viewModel.loadPreview(for: try #require(viewModel.entry(id: draft.id)))

        let preview = try #require(viewModel.preview)
        #expect(preview.planID == draft.id)
        #expect(preview.hasActivePlan)
        #expect(!preview.days.isEmpty)
        // Ten workouts build more fitness than three.
        #expect(preview.draftPeakCTL > preview.activePeakCTL)
        #expect(model.plans == plansBefore)
    }

    @Test("a plan with no upcoming workouts has no preview and says so")
    func previewOfEmptyPlan() async throws {
        let (_, model) = try await makeModel()
        let empty = try await model.createTrainingPlan(named: "Empty", asOf: today)
        let viewModel = makeViewModel(model)
        await viewModel.reload()

        await viewModel.loadPreview(for: try #require(viewModel.entry(id: empty.id)))

        #expect(viewModel.preview == nil)
        #expect(viewModel.previewMessage != nil)
    }

    @Test("the Watch sync schedules only the active plan's workouts")
    func watchFollowsActivePlan() async throws {
        let (store, model) = try await makeModel()
        let live = try await addPlan("Live", status: .active, workouts: 1, to: model, store: store)
        let draft = try await addPlan("Draft", status: .draft, workouts: 1, to: model, store: store)
        let scheduler = FakeScheduler()
        let sync = WatchScheduleSync(model: model, scheduler: scheduler, defaults: ScratchDefaults().defaults)

        await sync.sync(asOf: today)

        let liveIDs = Set(try await store.plans(in: day(-30)...day(60)).filter { $0.planID == live.id }.map(\.id))
        let draftIDs = Set(try await store.plans(in: day(-30)...day(60)).filter { $0.planID == draft.id }.map(\.id))
        let scheduled = Set(await scheduler.scheduledPlans.map(\.id))
        #expect(scheduled == liveIDs)
        #expect(scheduled.isDisjoint(with: draftIDs))
    }

    @Test("the micro-cycle view model drops cycles peeked from the previous plan when the plan changes")
    func microCycleViewModelFollowsActivePlan() async throws {
        let (store, model) = try await makeModel()
        let live = try await addPlan("Live", status: .active, workouts: 1, to: model, store: store)
        let draft = try await addPlan("Draft", status: .draft, workouts: 1, to: model, store: store)
        let cycle = TrainingCycle(
            level: .micro, phase: .base, loadRole: .build, name: "Draft micro",
            dateRange: day(0)...day(6), planID: draft.id
        )
        try await store.upsert([cycle])
        let micro = MicroCycleViewModel(model: model, refresher: FakeRefresher(), today: today)
        micro.anchorDate = day(2)
        await micro.load(asOf: today)
        #expect(micro.peekedCycles.isEmpty)

        try await model.activateTrainingPlan(id: draft.id, asOf: today)
        await micro.activePlanChanged(asOf: today)
        #expect(micro.peekedCycles.map(\.id) == [cycle.id])

        try await model.activateTrainingPlan(id: live.id, asOf: today)
        await micro.activePlanChanged(asOf: today)
        #expect(micro.peekedCycles.isEmpty)
    }

    @Test("creates an empty draft, refuses a blank name, and exposes the active plan")
    func createsDraftAndExposesActive() async throws {
        let (store, model) = try await makeModel()
        let viewModel = makeViewModel(model)
        await viewModel.reload()
        #expect(viewModel.activeEntry == nil)

        #expect(await viewModel.create(named: "   ") == nil)
        #expect(viewModel.actionError != nil)

        let created = await viewModel.create(named: " Spring ")
        #expect(created?.name == "Spring")
        #expect(viewModel.entries.map(\.plan.name) == ["Spring"])
        #expect(viewModel.entries.first?.plan.status == .draft)
        #expect(viewModel.actionError == nil)

        let live = try await addPlan("Live", status: .active, workouts: 1, to: model, store: store)
        await viewModel.reload()
        #expect(viewModel.activeEntry?.id == live.id)
    }

    @Test("the micro-cycle view keeps its calendar when every plan is archived")
    func calendarStaysWithOnlyArchivedPlans() async throws {
        let (store, model) = try await makeModel()
        let live = try await addPlan("Live", status: .active, workouts: 1, to: model, store: store)
        let micro = MicroCycleViewModel(model: model, refresher: FakeRefresher(), today: today)
        await micro.load(asOf: today)
        let viewModel = makeViewModel(model)
        try await model.setStatus(.archived, ofTrainingPlan: live.id, asOf: today)
        await viewModel.reload()
        await micro.activePlanChanged(asOf: today)

        #expect(model.plans.isEmpty)
        #expect(!micro.showsEmptyState)
    }

    @Test("today comes from the injected clock")
    func todayIsInjected() async throws {
        let (_, model) = try await makeModel()
        #expect(makeViewModel(model).today() == today)
    }
}
