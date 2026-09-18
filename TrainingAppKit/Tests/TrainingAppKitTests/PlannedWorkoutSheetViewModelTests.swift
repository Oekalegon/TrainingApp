import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@MainActor
@Suite("PlannedWorkoutSheetViewModel")
struct PlannedWorkoutSheetViewModelTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func makeModel() async -> (InMemoryStore, TrainingModel) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, athleteStore: store
        )
        let athlete = AthleteProfile.fixture(
            timeZoneIdentifier: "UTC", restingHeartRateBPM: 50, maxHeartRateBPM: 190
        )
        // `TrainingModel.athlete` is a plain, caller-managed property -- it's never persisted to
        // `athleteStore` on its own. `PlanSandbox.init` reads the athlete from the *store*, not
        // from `model.athlete`, so without this save it throws `missingAthleteProfile` on every
        // guardrail recompute -- silently, since `scheduleGuardrailRecompute()` swallows that error
        // with `try?`, which is exactly how this test setup bug first surfaced as "no guardrails".
        try? await store.save(athlete)
        return (store, TrainingModel(stores: stores, athlete: athlete))
    }

    @Test("selecting a template seeds parameter values and computes expectedLoad")
    func selectingTemplateSeedsDefaultsAndLoad() async {
        let (_, model) = await makeModel()
        let viewModel = PlannedWorkoutSheetViewModel(model: model, date: day(0))

        viewModel.selectedTemplate = BuiltInWorkoutTemplates.recoveryRun

        #expect(viewModel.parameterValues["duration"] == BuiltInWorkoutTemplates.recoveryRun.parameters[0].defaultValue)
        #expect(viewModel.workoutName == "Recovery run")
        #expect(viewModel.expectedLoad != nil)
    }

    @Test("setParameterValue(_:forKey:) recomputes expectedLoad, larger duration means more load")
    func settingParameterRecomputesLoad() async {
        let (_, model) = await makeModel()
        let viewModel = PlannedWorkoutSheetViewModel(model: model, date: day(0))
        viewModel.selectedTemplate = BuiltInWorkoutTemplates.recoveryRun
        let shortLoad = viewModel.expectedLoad?.value

        viewModel.setParameterValue(40 * 60, forKey: "duration")

        #expect(shortLoad != nil)
        #expect(viewModel.expectedLoad?.value ?? 0 > shortLoad ?? 0)
    }

    @Test("guardrail simulation never mutates the real stores")
    func guardrailSimulationDoesNotMutateRealStores() async {
        let (_, model) = await makeModel()
        try? await model.load(in: day(-7)...day(7))
        let viewModel = PlannedWorkoutSheetViewModel(model: model, date: day(0))

        viewModel.selectedTemplate = BuiltInWorkoutTemplates.recoveryRun
        await viewModel.waitForGuardrailRecompute()

        #expect(model.plans.isEmpty)
        #expect(model.workouts.isEmpty)
    }

    @Test("guardrail findings for a history-thin athlete stay scoped to the window around date, not the whole ~1.5-year sandbox range")
    func guardrailFindingsAreScopedNearDate() async {
        let (_, model) = await makeModel()
        let plannedDate = day(400)
        let viewModel = PlannedWorkoutSheetViewModel(model: model, date: plannedDate)

        viewModel.selectedTemplate = BuiltInWorkoutTemplates.recoveryRun
        await viewModel.waitForGuardrailRecompute()

        // A history-thin athlete's near-zero CTL/ATL can breach the ATL/CTL guardrail for hundreds
        // of consecutive days in the unscoped range -- this is the regression this test guards.
        #expect(viewModel.guardrailFindings.count <= 15)
        for finding in viewModel.guardrailFindings {
            #expect(finding.day >= plannedDate)
            #expect(finding.day <= plannedDate.addingTimeInterval(14 * 86400))
        }
        // With zero real activity history, every day in the display window is still
        // `FitnessMetrics.isWarmingUp` -- the diagnostic should say so rather than silently
        // reading as "nothing to flag".
        #expect(viewModel.guardrailDiagnostic != nil)
    }

    @Test("a big addition on top of an established training history still produces a guardrail finding despite date carrying a non-midnight time-of-day")
    func largeAdditionStillProducesFindingsDespiteTimeOfDay() async {
        let (store, model) = await makeModel()
        // `day(_:)` itself is already not midnight-aligned (epoch 1_700_000_000 is 22:13:20 UTC) --
        // exactly the regression this guards: a finding on `plannedDate`'s own calendar day must
        // not be dropped just because `plannedDate` carries a later time-of-day than that day's
        // PlanFinding/FitnessMetrics entries (which are always midnight-aligned).
        let plannedDate = day(400)
        // 60 days of a modest, steady easy run: enough real history for CTL/ATL to clear the
        // ~42-day warmup and settle into an established (low, steady) trend by `plannedDate`, so
        // a 35km long run on top of it reads as a genuine ATL spike rather than the warmup-day
        // guard skipping everything (an empty-history athlete's plan is a single-day series that
        // never leaves warmup, which is why this seeds real activities rather than testing bare).
        let history = (1...60).map { offset in
            Activity(
                source: .manual, sport: .running, start: plannedDate.addingTimeInterval(Double(-offset) * 86400),
                duration: 1800, perceivedExertion: 4
            )
        }
        try? await store.upsert(history)
        let viewModel = PlannedWorkoutSheetViewModel(model: model, date: plannedDate)

        viewModel.selectedTemplate = BuiltInWorkoutTemplates.longRun
        viewModel.setParameterValue(35_000, forKey: "distance")
        await viewModel.waitForGuardrailRecompute()

        #expect(!viewModel.guardrailFindings.isEmpty)
        #expect(viewModel.guardrailFindings.contains { $0.rule == .atlToCTLRatio && $0.severity == .risk })
        #expect(viewModel.guardrailDiagnostic == nil)
    }

    @Test("save() persists a library workout and a matching planned activity")
    func saveAddsWorkoutAndPlan() async {
        let (_, model) = await makeModel()
        // `scheduler: nil` -- the real WorkoutKitBridge's `schedule` requires a genuine app bundle
        // context and crashes when called from this test executable.
        let viewModel = PlannedWorkoutSheetViewModel(model: model, date: day(2), scheduler: nil)
        viewModel.selectedTemplate = BuiltInWorkoutTemplates.recoveryRun

        let didSave = await viewModel.save()

        #expect(didSave)
        #expect(model.workouts.count == 1)
        #expect(model.plans.count == 1)
        #expect(model.plans.first?.workoutID == model.workouts.first?.id)
        #expect(viewModel.saveError == nil)
    }

    @Test("save() fails without a selected template")
    func saveFailsWithoutTemplate() async {
        let (_, model) = await makeModel()
        let viewModel = PlannedWorkoutSheetViewModel(model: model, date: day(0), scheduler: nil)

        let didSave = await viewModel.save()

        #expect(!didSave)
        #expect(model.workouts.isEmpty)
    }

    @Test("save() syncs through the injected scheduler and persists its workoutKitID")
    func saveSyncsThroughScheduler() async {
        let (_, model) = await makeModel()
        let scheduler = FakeScheduler()
        let viewModel = PlannedWorkoutSheetViewModel(model: model, date: day(1), scheduler: scheduler)
        viewModel.selectedTemplate = BuiltInWorkoutTemplates.recoveryRun

        let didSave = await viewModel.save()

        #expect(didSave)
        #expect(model.workouts.first?.workoutKitID == scheduler.mintedID)
        #expect(await scheduler.scheduledPlans.count == 1)
    }
}

private final actor FakeScheduler: PlannedWorkoutScheduling {
    nonisolated let mintedID = UUID()
    private(set) var scheduledPlans: [PlannedActivity] = []

    func sync(_ workout: StructuredWorkout) async throws -> UUID {
        mintedID
    }

    func schedule(_ plan: PlannedActivity, workout: StructuredWorkout, calendar: Calendar) async throws {
        scheduledPlans.append(plan)
    }
}
