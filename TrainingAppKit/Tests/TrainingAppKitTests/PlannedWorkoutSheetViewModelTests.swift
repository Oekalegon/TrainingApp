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
        // Empty findings get a raw-numbers diagnostic instead of reading as silent "nothing to
        // flag" -- doesn't assert the exact text, just that one is present.
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
        // guard skipping everything.
        let history = (1...60).map { offset in
            Activity(
                source: .manual, sport: .running, start: plannedDate.addingTimeInterval(Double(-offset) * 86400),
                duration: 1800, perceivedExertion: 4
            )
        }
        try? await store.upsert(history)
        // `recomputeGuardrails()` seeds from `model.metrics`, which only reflects what `load(in:)`
        // last pulled from the store -- seeding the store alone (as above) doesn't populate it.
        try? await model.load(in: plannedDate.addingTimeInterval(-70 * 86400)...plannedDate)
        let viewModel = PlannedWorkoutSheetViewModel(model: model, date: plannedDate)

        viewModel.selectedTemplate = BuiltInWorkoutTemplates.longRun
        viewModel.setParameterValue(35_000, forKey: "distance")
        await viewModel.waitForGuardrailRecompute()

        #expect(!viewModel.guardrailFindings.isEmpty)
        // TSB is the direct freshness signal -- the day after the addition should read as a
        // genuine risk-level dip.
        #expect(viewModel.guardrailFindings.contains { $0.rule == .tsbBand && $0.severity == .risk })
        // atlToCTLRatio isn't filtered here anymore -- that hypersensitive-at-low-CTL problem
        // (a real report: CTL=9, ATL=14, TSB=-6, unremarkable per tsbBand, already read as
        // ratio=1.56, over the risk threshold) is now gated at the source by TrainingKit's
        // `PlanGuardrails.minCTLForRatioCheck`. This test's 60-day established history clears
        // that minimum, so the ratio check legitimately applies -- unlike the low-CTL case, this
        // isn't a false positive to suppress.
        // Always populated now (not just when there are no findings), so "what would tomorrow's
        // TSB/ratio be" is directly checkable from the sheet.
        #expect(viewModel.guardrailDiagnostic != nil)
        #expect(viewModel.guardrailDiagnostic?.contains("ratio=") == true)

        // The recovery from a single big addition spans several consecutive days per rule --
        // guardrailSummaries should collapse each rule's run(s) into far fewer rows than one per
        // day, though not necessarily exactly one per rule: a rule can dip out of band, briefly
        // recover, then dip again, which is genuinely two separate runs (contiguity is checked
        // precisely by the dedicated grouping test below).
        #expect(viewModel.guardrailSummaries.count < viewModel.guardrailFindings.count)
        let distinctRules = Set(viewModel.guardrailFindings.map(\.rule))
        #expect(Set(viewModel.guardrailSummaries.map(\.rule)) == distinctRules)
    }

    @Test("guardrailSummaries collapses a contiguous run of the same rule into one entry with a day range")
    func guardrailSummariesCollapseContiguousRuns() async {
        let (_, model) = await makeModel()
        let viewModel = PlannedWorkoutSheetViewModel(model: model, date: day(0))
        viewModel.selectedTemplate = BuiltInWorkoutTemplates.recoveryRun

        // Synthesize three consecutive days of the same rule plus one separate day, bypassing the
        // real projection (already covered by other tests) to test the grouping logic in isolation.
        let findings = [
            PlanFinding(day: day(0), rule: .tsbBand, severity: .warning, value: 30, threshold: 25),
            PlanFinding(day: day(1), rule: .tsbBand, severity: .risk, value: -40, threshold: -30),
            PlanFinding(day: day(2), rule: .tsbBand, severity: .warning, value: 28, threshold: 25),
            PlanFinding(day: day(5), rule: .atlToCTLRatio, severity: .risk, value: 1.6, threshold: 1.4),
        ]
        viewModel.setGuardrailFindingsForTesting(findings)

        let summaries = viewModel.guardrailSummaries
        #expect(summaries.count == 2)
        let tsbSummary = summaries.first { $0.rule == .tsbBand }
        #expect(tsbSummary?.dayCount == 3)
        #expect(tsbSummary?.firstDay == day(0))
        #expect(tsbSummary?.lastDay == day(2))
        // Worst severity across the run, not the first/last day's own.
        #expect(tsbSummary?.severity == .risk)
        let ratioSummary = summaries.first { $0.rule == .atlToCTLRatio }
        #expect(ratioSummary?.dayCount == 1)
        // Sorted worst-severity first; both runs here are .risk, so earliest day breaks the tie.
        #expect(summaries.first?.rule == .tsbBand)
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

    @Test("save() persists nothing when schedule() fails, rather than leaving an orphaned library workout")
    func saveLeavesNoOrphanWhenScheduleFails() async {
        let (_, model) = await makeModel()
        let scheduler = FakeScheduler(scheduleShouldFail: true)
        let viewModel = PlannedWorkoutSheetViewModel(model: model, date: day(1), scheduler: scheduler)
        viewModel.selectedTemplate = BuiltInWorkoutTemplates.recoveryRun

        let didSave = await viewModel.save()

        #expect(!didSave)
        #expect(viewModel.saveError != nil)
        // sync() succeeded (that's what schedule() draws its CustomWorkout mapping from too), but
        // schedule() failing must not leave the workout it already validated sitting in the
        // library with nothing referencing it.
        #expect(model.workouts.isEmpty)
        #expect(model.plans.isEmpty)
    }

    @Test("a second concurrent save() call is a no-op while the first is still in flight")
    func concurrentSaveCallsDoNotDoubleSave() async {
        let (_, model) = await makeModel()
        let scheduler = FakeScheduler()
        let viewModel = PlannedWorkoutSheetViewModel(model: model, date: day(1), scheduler: scheduler)
        viewModel.selectedTemplate = BuiltInWorkoutTemplates.recoveryRun

        async let first = viewModel.save()
        async let second = viewModel.save()
        let (firstResult, secondResult) = await (first, second)

        // Exactly one of the two actually saved -- both racing to `true` (or both silently
        // dropping to `false`) would either double-persist or silently lose the save.
        #expect(firstResult != secondResult)
        #expect(model.workouts.count == 1)
        #expect(model.plans.count == 1)
    }

    @Test("minimumDate(asOf:) is the given day's calendar start in the athlete's timezone")
    func minimumDateIsStartOfGivenDayInAthleteTimeZone() async {
        let (_, model) = await makeModel()
        let viewModel = PlannedWorkoutSheetViewModel(model: model, date: day(0))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = model.athlete.timeZone
        // Pinned to day(5) rather than .now -- matches WeekViewModel.isPast(_:asOf:)'s own
        // injectable-`today` convention, so this doesn't race a real midnight boundary.
        #expect(viewModel.minimumDate(asOf: day(5)) == calendar.startOfDay(for: day(5)))
    }
}

private final actor FakeScheduler: PlannedWorkoutScheduling {
    nonisolated let mintedID = UUID()
    private let scheduleShouldFail: Bool
    private(set) var scheduledPlans: [PlannedActivity] = []

    init(scheduleShouldFail: Bool = false) {
        self.scheduleShouldFail = scheduleShouldFail
    }

    func sync(_ workout: StructuredWorkout) async throws -> UUID {
        mintedID
    }

    func schedule(_ plan: PlannedActivity, workout: StructuredWorkout, calendar: Calendar) async throws {
        if scheduleShouldFail {
            struct SchedulingFailed: Error {}
            throw SchedulingFailed()
        }
        scheduledPlans.append(plan)
    }
}
