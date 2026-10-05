import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@MainActor
@Suite("WorkoutLibraryViewModel")
struct WorkoutLibraryViewModelTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func makeModel() async -> (InMemoryStore, TrainingModel) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        let athlete = AthleteProfile.fixture(
            timeZoneIdentifier: "UTC", restingHeartRateBPM: 50, maxHeartRateBPM: 190
        )
        try? await store.save(athlete)
        return (store, TrainingModel(stores: stores, athlete: athlete))
    }

    private func makeViewModel(model: TrainingModel, templates: [WorkoutTemplate] = BuiltInWorkoutTemplates.all) -> WorkoutLibraryViewModel {
        let viewModel = WorkoutLibraryViewModel(model: model, templates: templates, scheduler: { nil })
        viewModel.distanceSystem = .metric
        return viewModel
    }

    /// Stores a workout made from `template` and a plan for it on each of `days`.
    private func plan(
        _ template: WorkoutTemplate, on days: [Date], completed: Bool = false, in store: InMemoryStore
    ) async throws {
        let workout = try template.instantiate()
        try await store.upsert([workout])
        try await store.upsert(days.map {
            PlannedActivity(workoutID: workout.id, date: $0, completedActivityID: completed ? UUID() : nil)
        })
    }

    @Test("lists every template, grouped by sport in the templates' order")
    func listsTemplatesBySport() async {
        let (_, model) = await makeModel()
        let ride = WorkoutTemplate(
            name: "Steady ride", sport: .cycling,
            parameters: [], blocks: [TemplateBlock(steps: [TemplateStep(kind: .work, goal: .time(.fixed(3600)), target: .heartRateZone(2))])]
        )
        let viewModel = makeViewModel(model: model, templates: [BuiltInWorkoutTemplates.easyRun, ride, BuiltInWorkoutTemplates.longRun])

        let sections = viewModel.sections(asOf: day(0))

        #expect(sections.map(\.sport) == [.running, .cycling])
        #expect(sections[0].entries.map(\.id) == [BuiltInWorkoutTemplates.easyRun.id, BuiltInWorkoutTemplates.longRun.id])
        #expect(sections[1].entries.map(\.id) == [ride.id])
    }

    @Test("search matches every word against the name, default title and sport, ignoring case")
    func searchFiltersEntries() async {
        let (_, model) = await makeModel()
        let viewModel = makeViewModel(model: model)
        func ids(_ query: String) -> [UUID] {
            viewModel.entries(matching: query, asOf: day(0)).map(\.id)
        }

        #expect(ids("") == BuiltInWorkoutTemplates.all.map(\.id))
        #expect(ids("EASY") == [BuiltInWorkoutTemplates.easyRun.id])
        // By default title ("20 km Long Run") and across words in any order.
        #expect(ids("km long") == [BuiltInWorkoutTemplates.longRun.id])
        #expect(ids("run long") == [BuiltInWorkoutTemplates.longRun.id])
        // By sport.
        #expect(ids("running").count == BuiltInWorkoutTemplates.all.count)
        #expect(ids("swim").isEmpty)
    }

    @Test("an entry has the default title, the default steps and an estimated load")
    func entryShowsDefaults() async throws {
        let (_, model) = await makeModel()
        let viewModel = makeViewModel(model: model, templates: [BuiltInWorkoutTemplates.easyRun])

        let entry = try #require(viewModel.entries(asOf: day(0)).first)

        #expect(entry.defaultTitle == "40min Easy Run")
        // 5 min warm-up, 30 min easy, 5 min cool-down.
        let defaultWorkout = try BuiltInWorkoutTemplates.easyRun.instantiate()
        #expect(entry.stepLines == defaultWorkout.blocks.map { PlannedWorkoutDetailViewModel.line(for: $0) })
        #expect(entry.stepLines.count == 3)
        #expect((entry.expectedLoad ?? 0) > 0)
        #expect(entry.planCount == 0)
        #expect(entry.nextPlannedDate == nil)
    }

    @Test("counts every plan made from a template once reloaded, and finds the next one due")
    func countsPlansAfterReload() async throws {
        let (store, model) = await makeModel()
        try await plan(BuiltInWorkoutTemplates.easyRun, on: [day(-10), day(3), day(1)], in: store)
        try await plan(BuiltInWorkoutTemplates.longRun, on: [day(5)], completed: true, in: store)
        // Built by hand: belongs to no template.
        let custom = StructuredWorkout(name: "Custom", sport: .running, blocks: [])
        try await store.upsert([custom])
        try await store.upsert([PlannedActivity(workoutID: custom.id, date: day(2))])
        let viewModel = makeViewModel(model: model)

        #expect(viewModel.entries(asOf: day(0)).allSatisfy { $0.planCount == 0 })

        await viewModel.reload()
        let entries = Dictionary(uniqueKeysWithValues: viewModel.entries(asOf: day(0)).map { ($0.id, $0) })

        let easy = try #require(entries[BuiltInWorkoutTemplates.easyRun.id])
        #expect(easy.planCount == 3)
        #expect(easy.nextPlannedDate == day(1))
        // A done plan still counts, but isn't "next".
        let long = try #require(entries[BuiltInWorkoutTemplates.longRun.id])
        #expect(long.planCount == 1)
        #expect(long.nextPlannedDate == nil)
        #expect(entries[BuiltInWorkoutTemplates.recoveryRun.id]?.planCount == 0)
        #expect(viewModel.loadError == nil)
    }

    @Test("the planner opens with the template picked, and saving reloads the counts")
    func plannerPicksTemplateAndReloads() async throws {
        let (_, model) = await makeModel()
        let viewModel = makeViewModel(model: model)
        let changes = ChangeCounter()
        viewModel.onPlansChanged = { changes.count += 1 }

        let planner = viewModel.makePlanner(for: BuiltInWorkoutTemplates.easyRun, date: day(1))
        #expect(planner.selectedTemplate?.id == BuiltInWorkoutTemplates.easyRun.id)
        #expect(planner.workoutName == "40min Easy Run")

        #expect(await planner.save(asOf: day(0)))
        #expect(changes.count == 1)

        await viewModel.pendingReload?.value
        let easy = viewModel.entries(asOf: day(0)).first { $0.id == BuiltInWorkoutTemplates.easyRun.id }
        #expect(easy?.planCount == 1)
        #expect(easy?.nextPlannedDate == day(1))
    }

    // MARK: Watch setting (MVP2-118)

    private let scratch = ScratchDefaults()

    @Test("a plan made from the tab goes to the Watch only while sending is on")
    func plannerFollowsWatchSetting() async throws {
        let (_, model) = await makeModel()
        let scheduler = FakeScheduler()
        let sync = WatchScheduleSync(model: model, scheduler: scheduler, defaults: scratch.defaults)
        let week = WeekViewModel(model: model, refresher: FakeRefresher(), watchSync: sync, today: day(0))
        let library = week.workoutLibraryViewModel()

        await sync.setEnabled(false, asOf: day(0)).value
        let off = library.makePlanner(for: BuiltInWorkoutTemplates.easyRun, date: day(0))
        #expect(await off.save(asOf: day(0)))
        #expect(await scheduler.scheduledPlans.isEmpty)

        // Asked again when the next sheet opens, so turning sending back on takes effect at once.
        await sync.setEnabled(true, asOf: day(0)).value
        let on = library.makePlanner(for: BuiltInWorkoutTemplates.recoveryRun, date: day(0))
        #expect(await on.save(asOf: day(0)))
        let recoveryPlanIDs = Set(model.plans.filter { plan in
            model.workouts.first { $0.id == plan.workoutID }?.templateID == BuiltInWorkoutTemplates.recoveryRun.id
        }.map(\.id))
        #expect(recoveryPlanIDs.count == 1)
        #expect(await scheduler.scheduledPlans.contains { recoveryPlanIDs.contains($0.id) })
    }
}
