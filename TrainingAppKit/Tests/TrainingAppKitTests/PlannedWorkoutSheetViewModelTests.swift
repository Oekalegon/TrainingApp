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

    // MARK: - Edit mode (MVP2-39)

    /// A plan scheduling a small, already-synced library workout, loaded into `model`.
    private func makeEditablePlan(
        model: TrainingModel, on date: Date, override: Double? = nil, synced: Bool = true
    ) async throws -> (PlannedActivity, StructuredWorkout) {
        var workout = StructuredWorkout(
            name: "Steady", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800), target: .heartRateZone(2))])]
        )
        if synced {
            workout.workoutKitID = UUID()
        }
        let plan = PlannedActivity(workoutID: workout.id, date: date, expectedLoadOverride: override)
        try await model.add(workout)
        try await model.add(plan)
        return (plan, workout)
    }

    @Test("editing seeds date, override and expected load from the plan, and exposes the workout read-only")
    func editingSeedsFromPlan() async throws {
        let (_, model) = await makeModel()
        try await model.load(in: day(-7)...day(14))
        let (plan, _) = try await makeEditablePlan(model: model, on: day(3), override: 77)

        let viewModel = PlannedWorkoutSheetViewModel(model: model, editing: plan, scheduler: nil)

        #expect(viewModel.isEditing)
        #expect(viewModel.date == day(3))
        #expect(viewModel.loadOverride == 77)
        #expect(viewModel.editedWorkoutName == "Steady")
        #expect(viewModel.expectedLoad?.value == 77)
        #expect(viewModel.guardrailDiagnostic != nil)
    }

    @Test("editing's loadOverride replaces the estimate in expectedLoad and clearing it restores the estimate")
    func editingOverrideReplacesEstimate() async throws {
        let (_, model) = await makeModel()
        try await model.load(in: day(-7)...day(14))
        let (plan, _) = try await makeEditablePlan(model: model, on: day(3))
        let viewModel = PlannedWorkoutSheetViewModel(model: model, editing: plan, scheduler: nil)
        let estimate = try #require(viewModel.expectedLoad?.value)

        viewModel.loadOverride = estimate + 100
        #expect(viewModel.expectedLoad?.value == estimate + 100)

        viewModel.loadOverride = nil
        #expect(viewModel.expectedLoad?.value == estimate)
    }

    @Test("saving an edit that changes only the override updates the plan in place and never touches WorkoutKit")
    func editOverrideOnlyDoesNotReschedule() async throws {
        let (_, model) = await makeModel()
        try await model.load(in: day(-7)...day(14))
        let (plan, _) = try await makeEditablePlan(model: model, on: day(3))
        let scheduler = FakeScheduler()
        let viewModel = PlannedWorkoutSheetViewModel(model: model, editing: plan, scheduler: scheduler)

        viewModel.loadOverride = 42
        let didSave = await viewModel.save()

        #expect(didSave)
        #expect(model.plans.count == 1)
        #expect(model.plans.first?.id == plan.id)
        #expect(model.plans.first?.expectedLoadOverride == 42)
        #expect(model.plans.first?.date == day(3))
        #expect(await scheduler.callLog.isEmpty)
    }

    @Test("saving an edit that moves the day schedules the new day first, then removes the old one")
    func editMovingDayReschedules() async throws {
        let (_, model) = await makeModel()
        try await model.load(in: day(-7)...day(14))
        let (plan, _) = try await makeEditablePlan(model: model, on: day(3))
        let scheduler = FakeScheduler()
        let viewModel = PlannedWorkoutSheetViewModel(model: model, editing: plan, scheduler: scheduler)

        viewModel.date = day(5)
        let didSave = await viewModel.save()

        #expect(didSave)
        #expect(model.plans.count == 1)
        #expect(model.plans.first?.date == day(5))
        #expect(await scheduler.callLog == ["schedule", "unschedule"])
        #expect(await scheduler.scheduledPlans.first?.date == day(5))
        #expect(await scheduler.unscheduledPlans.first?.date == day(3))
    }

    @Test("a failed reschedule leaves the plan on its old day and reports the error")
    func editRescheduleFailureLeavesPlanUntouched() async throws {
        let (_, model) = await makeModel()
        try await model.load(in: day(-7)...day(14))
        let (plan, _) = try await makeEditablePlan(model: model, on: day(3))
        let scheduler = FakeScheduler(scheduleShouldFail: true)
        let viewModel = PlannedWorkoutSheetViewModel(model: model, editing: plan, scheduler: scheduler)

        viewModel.date = day(5)
        let didSave = await viewModel.save()

        #expect(!didSave)
        #expect(viewModel.saveError != nil)
        #expect(model.plans.first?.date == day(3))
        #expect(await scheduler.unscheduledPlans.isEmpty)
    }

    @Test("moving a never-synced workout adopts a WorkoutKit id so the new entry can be found later")
    func editMovingUnsyncedWorkoutAdoptsID() async throws {
        let (_, model) = await makeModel()
        try await model.load(in: day(-7)...day(14))
        let (plan, workout) = try await makeEditablePlan(model: model, on: day(3), synced: false)
        let scheduler = FakeScheduler()
        let viewModel = PlannedWorkoutSheetViewModel(model: model, editing: plan, scheduler: scheduler)

        viewModel.date = day(5)
        #expect(await viewModel.save())

        #expect(model.workouts.first { $0.id == workout.id }?.workoutKitID == scheduler.mintedID)
    }

    @Test("editing a plan whose workout left the library still saves, without a name or any WorkoutKit call")
    func editOrphanedPlan() async throws {
        let (_, model) = await makeModel()
        try await model.load(in: day(-7)...day(14))
        let orphan = PlannedActivity(workoutID: UUID(), date: day(3))
        try await model.add(orphan)
        let scheduler = FakeScheduler()
        let viewModel = PlannedWorkoutSheetViewModel(model: model, editing: orphan, scheduler: scheduler)

        #expect(viewModel.editedWorkoutName == nil)
        viewModel.date = day(5)
        #expect(await viewModel.save())

        #expect(model.plans.first?.date == day(5))
        #expect(await scheduler.callLog.isEmpty)
    }

    @Test("minimumDate in edit mode reaches back to a past plan's own day, never before it")
    func editMinimumDateIncludesPastPlanDay() async throws {
        let (_, model) = await makeModel()
        try await model.load(in: day(-7)...day(14))
        let (plan, _) = try await makeEditablePlan(model: model, on: day(1))
        let viewModel = PlannedWorkoutSheetViewModel(model: model, editing: plan, scheduler: nil)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = model.athlete.timeZone

        #expect(viewModel.minimumDate(asOf: day(5)) == calendar.startOfDay(for: day(1)))
        // A future plan keeps the normal "today" bound.
        let (future, _) = try await makeEditablePlan(model: model, on: day(9))
        let futureViewModel = PlannedWorkoutSheetViewModel(model: model, editing: future, scheduler: nil)
        #expect(futureViewModel.minimumDate(asOf: day(5)) == calendar.startOfDay(for: day(5)))
    }

    // MARK: - Editing parameters (MVP2-41)

    /// A plan scheduling a workout instantiated from the built-in recovery-run template, so it carries
    /// its template id and parameter values.
    private func makeTemplatePlan(
        model: TrainingModel, on date: Date, duration: Double = 20 * 60
    ) async throws -> (PlannedActivity, StructuredWorkout) {
        var workout = try BuiltInWorkoutTemplates.recoveryRun.instantiate(values: ["duration": duration])
        workout.workoutKitID = UUID()
        let plan = PlannedActivity(workoutID: workout.id, date: date)
        try await model.add(workout)
        try await model.add(plan)
        return (plan, workout)
    }

    @Test("editing a template-built plan seeds the recorded parameter values and offers its parameters")
    func editingSeedsParameters() async throws {
        let (_, model) = await makeModel()
        try await model.load(in: day(-7)...day(14))
        let (plan, _) = try await makeTemplatePlan(model: model, on: day(3), duration: 35 * 60)

        let viewModel = PlannedWorkoutSheetViewModel(model: model, editing: plan, scheduler: nil)

        #expect(viewModel.canEditParameters)
        #expect(viewModel.editableParameters.map(\.key) == BuiltInWorkoutTemplates.recoveryRun.parameters.map(\.key))
        #expect(viewModel.parameterValues["duration"] == 35.0 * 60)
    }

    @Test("a workout without a recorded template can't have its parameters edited")
    func editingLegacyWorkoutHasNoParameters() async throws {
        let (_, model) = await makeModel()
        try await model.load(in: day(-7)...day(14))
        let workout = StructuredWorkout(
            name: "Old", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800), target: .heartRateZone(2))])]
        )
        let plan = PlannedActivity(workoutID: workout.id, date: day(3))
        try await model.add(workout)
        try await model.add(plan)

        let viewModel = PlannedWorkoutSheetViewModel(model: model, editing: plan, scheduler: nil)

        #expect(!viewModel.canEditParameters)
        #expect(viewModel.editableParameters.isEmpty)
    }

    @Test("changing a parameter in edit mode updates the expected load")
    func editingParameterUpdatesLoad() async throws {
        let (_, model) = await makeModel()
        try await model.load(in: day(-7)...day(14))
        let (plan, _) = try await makeTemplatePlan(model: model, on: day(3), duration: 20 * 60)
        let viewModel = PlannedWorkoutSheetViewModel(model: model, editing: plan, scheduler: nil)
        let before = try #require(viewModel.expectedLoad?.value)

        viewModel.setParameterValue(60 * 60, forKey: "duration")

        #expect((viewModel.expectedLoad?.value ?? 0) > before)
    }

    @Test("saving a parameter change gives the plan a new workout, reschedules it, and removes the unshared old one")
    func saveParameterChangeReplacesWorkout() async throws {
        let (_, model) = await makeModel()
        try await model.load(in: day(-7)...day(14))
        let (plan, oldWorkout) = try await makeTemplatePlan(model: model, on: day(3), duration: 20 * 60)
        let scheduler = FakeScheduler()
        let viewModel = PlannedWorkoutSheetViewModel(model: model, editing: plan, scheduler: scheduler)

        viewModel.setParameterValue(45 * 60, forKey: "duration")
        let didSave = await viewModel.save()

        #expect(didSave)
        let saved = try #require(model.plans.first { $0.id == plan.id })
        #expect(saved.workoutID != oldWorkout.id)
        let newWorkout = try #require(model.workouts.first { $0.id == saved.workoutID })
        #expect(newWorkout.name == oldWorkout.name)
        #expect(newWorkout.templateID == oldWorkout.templateID)
        #expect(newWorkout.parameterValues?["duration"] == 45.0 * 60)
        #expect(!model.workouts.contains { $0.id == oldWorkout.id })
        #expect(await scheduler.callLog == ["schedule", "unschedule"])
    }

    @Test("saving a parameter change keeps the old workout when another plan still uses it")
    func saveParameterChangeKeepsSharedWorkout() async throws {
        let (_, model) = await makeModel()
        try await model.load(in: day(-7)...day(14))
        let (plan, oldWorkout) = try await makeTemplatePlan(model: model, on: day(3))
        try await model.add(PlannedActivity(workoutID: oldWorkout.id, date: day(6)))
        let viewModel = PlannedWorkoutSheetViewModel(model: model, editing: plan, scheduler: nil)

        viewModel.setParameterValue(45 * 60, forKey: "duration")
        #expect(await viewModel.save())

        #expect(model.workouts.contains { $0.id == oldWorkout.id })
        #expect(model.plans.filter { $0.workoutID == oldWorkout.id }.count == 1)
    }

    @Test("saving without touching a parameter leaves the plan on its existing workout")
    func saveWithoutParameterChangeKeepsWorkout() async throws {
        let (_, model) = await makeModel()
        try await model.load(in: day(-7)...day(14))
        let (plan, oldWorkout) = try await makeTemplatePlan(model: model, on: day(3))
        let scheduler = FakeScheduler()
        let viewModel = PlannedWorkoutSheetViewModel(model: model, editing: plan, scheduler: scheduler)

        viewModel.loadOverride = 33
        #expect(await viewModel.save())

        #expect(model.plans.first?.workoutID == oldWorkout.id)
        #expect(model.workouts.count == 1)
        #expect(await scheduler.callLog.isEmpty)
    }

    @Test("a failed reschedule after a parameter change leaves the plan and its workout untouched")
    func parameterChangeRescheduleFailureLeavesEverythingUntouched() async throws {
        let (_, model) = await makeModel()
        try await model.load(in: day(-7)...day(14))
        let (plan, oldWorkout) = try await makeTemplatePlan(model: model, on: day(3))
        let scheduler = FakeScheduler(scheduleShouldFail: true)
        let viewModel = PlannedWorkoutSheetViewModel(model: model, editing: plan, scheduler: scheduler)

        viewModel.setParameterValue(45 * 60, forKey: "duration")
        #expect(!(await viewModel.save()))

        #expect(model.plans.first?.workoutID == oldWorkout.id)
        #expect(model.workouts.map(\.id) == [oldWorkout.id])
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
