import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@MainActor
@Suite("CreatePlanViewModel (MVP5-146)")
struct CreatePlanViewModelTests {
    /// A Tuesday, 22:13 UTC.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .init(identifier: "UTC")!
        return calendar
    }

    private func day(_ offset: Int) -> Date {
        utc.date(byAdding: .day, value: offset, to: utc.startOfDay(for: now))!
    }

    private var athleteAvailability: RunAvailability {
        var availability = RunAvailability()
        for weekday in [Weekday.tuesday, .thursday, .sunday] { availability[weekday] = [.morning] }
        return availability
    }

    private func makeModel(trainingPlans: Bool = true) async throws -> (InMemoryStore, TrainingModel) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store, cycleStore: store, raceStore: store,
            athleteStore: store, trainingPlanStore: trainingPlans ? store : nil
        )
        var athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC", restingHeartRateBPM: 50, maxHeartRateBPM: 190)
        athlete.runAvailability = athleteAvailability
        try await store.save(athlete)
        let model = TrainingModel(stores: stores, athlete: athlete)
        try await model.load(in: day(-30)...day(200), asOf: now)
        return (store, model)
    }

    private func makeViewModel(
        _ model: TrainingModel, generator: @escaping PlanGenerating = { try await PlanGenerator.generate($0) }
    ) -> CreatePlanViewModel {
        let now = now
        return CreatePlanViewModel(model: model, generator: generator, now: { now })
    }

    private func race(_ name: String, in days: Int, _ priority: RacePriority = .primary, meters: Double = Race.marathonDistanceMeters) -> Race {
        Race(name: name, date: day(days), priority: priority, distanceMeters: meters)
    }

    /// A view model with `races` stored and loaded, the first primary one ticked.
    private func loaded(_ races: [Race], generator: @escaping PlanGenerating = { try await PlanGenerator.generate($0) }) async throws -> (InMemoryStore, TrainingModel, CreatePlanViewModel) {
        let (store, model) = try await makeModel()
        try await store.upsert(races)
        let viewModel = makeViewModel(model, generator: generator)
        await viewModel.load()
        return (store, model, viewModel)
    }

    // MARK: Defaults and overrides

    @Test("the plan's availability starts as the athlete's and stays valid")
    func availabilityPrefilled() async throws {
        let (_, model) = try await makeModel()
        let viewModel = makeViewModel(model)

        #expect(viewModel.preferences.runAvailability == athleteAvailability)
        #expect(!viewModel.hasAvailabilityOverride)
        #expect(viewModel.problem(in: .preferences) == nil)
    }

    @Test("changing the availability for the plan never writes back to the athlete, and can be reset")
    func overrideIsPlanOnly() async throws {
        let (_, model) = try await makeModel()
        let viewModel = makeViewModel(model)
        var changed = RunAvailability()
        changed[.monday] = [.evening]

        viewModel.setAvailability(changed)

        #expect(viewModel.hasAvailabilityOverride)
        #expect(model.athlete.runAvailability == athleteAvailability)
        viewModel.resetAvailability()
        #expect(!viewModel.hasAvailabilityOverride)
    }

    @Test("the day-screen editor, wired the way the wizard wires it, edits the plan's availability only")
    func editorEditsPlanOnly() async throws {
        let (_, model) = try await makeModel()
        let viewModel = makeViewModel(model)
        let editor = RunAvailabilityEditor(
            saved: { viewModel.preferences.runAvailability },
            save: { viewModel.setAvailability($0); return true }
        )

        await editor.toggleDay(.monday)

        #expect(viewModel.preferences.runAvailability.isAvailable(on: .monday))
        #expect(editor.shown.isAvailable(on: .monday))
        #expect(!model.athlete.runAvailability.isAvailable(on: .monday))
        #expect(viewModel.hasAvailabilityOverride)
    }

    @Test("an empty availability blocks the preferences step")
    func emptyAvailabilityBlocks() async throws {
        let (_, model) = try await makeModel()
        let viewModel = makeViewModel(model)
        viewModel.setAvailability(RunAvailability())

        #expect(viewModel.problem(in: .preferences) != nil)
    }

    // MARK: Start date

    @Test("the start date defaults to today, is normalised to the start of a day and can't be in the past")
    func startDate() async throws {
        let (_, model) = try await makeModel()
        let viewModel = makeViewModel(model)

        #expect(viewModel.startDate == day(0))
        #expect(viewModel.problem(in: .startDate) == nil)
        viewModel.startDate = day(3).addingTimeInterval(7200)
        #expect(viewModel.startDate == day(3))
        viewModel.startDate = day(-2)
        #expect(viewModel.problem(in: .startDate) != nil)
    }

    // MARK: Races

    @Test("the nearest primary upcoming race is ticked after loading; earlier races are not offered")
    func loadsRaces() async throws {
        let (_, _, viewModel) = try await loaded([
            race("Old", in: -10), race("Tune-up", in: 40, .secondary), race("Marathon", in: 90), race("Later", in: 150)
        ])

        #expect(viewModel.upcomingRaces.map(\.name) == ["Tune-up", "Marathon", "Later"])
        #expect(viewModel.targetRace?.name == "Marathon")
        #expect(viewModel.problem(in: .races) == nil)
    }

    @Test("with no race ticked the races step names what is missing")
    func noRace() async throws {
        let (_, _, viewModel) = try await loaded([race("Tune-up", in: 40, .secondary)])

        #expect(viewModel.targetRace == nil)
        #expect(viewModel.problem(in: .races) != nil)
    }

    @Test("two primary races are refused until one is made secondary again, for this plan only")
    func twoPrimaries() async throws {
        let target = race("Spring", in: 80)
        let tuneUp = race("Tune-up", in: 50, .secondary)
        let (store, _, viewModel) = try await loaded([target, tuneUp])
        viewModel.toggle(tuneUp)
        #expect(viewModel.problem(in: .races) == nil)

        viewModel.setPriority(.primary, of: tuneUp)
        #expect(viewModel.problem(in: .races) != nil)
        #expect(viewModel.targetRace?.id == tuneUp.id)
        // The earlier race is now the target, so the later primary is outside the window.
        #expect(viewModel.windowState(of: target) == .afterTarget)

        viewModel.setPriority(.secondary, of: tuneUp)
        #expect(viewModel.problem(in: .races) == nil)
        #expect(viewModel.targetRace?.id == target.id)
        #expect(viewModel.includedRaces.map(\.priority) == [.secondary, .primary])
        let stored = try await store.races(in: day(0)...day(200))
        #expect(stored.first { $0.id == tuneUp.id }?.priority == .secondary)
    }

    @Test("a race made primary for this plan alone leaves the stored race as it was")
    func priorityOverrideIsPlanOnly() async throws {
        let tertiary = race("Parkrun", in: 30, .tertiary, meters: 5000)
        let (store, _, viewModel) = try await loaded([tertiary, race("Target", in: 90)])
        viewModel.toggle(tertiary)

        viewModel.setPriority(.secondary, of: tertiary)

        #expect(viewModel.includedRaces.first?.priority == .secondary)
        let stored = try await store.races(in: day(0)...day(200))
        #expect(stored.first { $0.id == tertiary.id }?.priority == .tertiary)
    }

    @Test("races after the target are outside the window and can't be ticked; those before the start are too")
    func raceWindow() async throws {
        let before = race("Before", in: 10, .secondary)
        let inside = race("Inside", in: 40, .secondary)
        let target = race("Target", in: 90)
        let after = race("After", in: 120, .secondary)
        let (_, _, viewModel) = try await loaded([before, inside, target, after])

        #expect(viewModel.windowState(of: inside) == .inWindow)
        #expect(viewModel.windowState(of: target) == .inWindow)
        #expect(viewModel.windowState(of: after) == .afterTarget)
        viewModel.toggle(after)
        #expect(!viewModel.selectedRaceIDs.contains(after.id))
        viewModel.toggle(inside)
        #expect(viewModel.includedRaces.map(\.name) == ["Inside", "Target"])

        viewModel.startDate = day(20)
        #expect(viewModel.windowState(of: before) == .beforeStart)
        viewModel.toggle(before)
        #expect(!viewModel.selectedRaceIDs.contains(before.id))
    }

    @Test("a ticked race that the start date moves past drops out of the included races")
    func startMovesPastRace() async throws {
        let inside = race("Inside", in: 15, .secondary)
        let (_, _, viewModel) = try await loaded([inside, race("Target", in: 90)])
        viewModel.toggle(inside)
        #expect(viewModel.includedRaces.count == 2)

        viewModel.startDate = day(30)

        #expect(viewModel.includedRaces.map(\.name) == ["Target"])
        #expect(viewModel.excludedRaces.map(\.name) == ["Inside"])
    }

    @Test("a race added from the shortcut is read back and ticked")
    func addedRaceIsSelected() async throws {
        let (store, model, viewModel) = try await loaded([race("Target", in: 90)])
        let added = race("Tune-up", in: 40, .secondary)
        try await store.upsert([added])
        _ = model

        await viewModel.raceWasAdded(added)

        #expect(viewModel.selectedRaceIDs.contains(added.id))
        #expect(viewModel.includedRaces.map(\.name) == ["Tune-up", "Target"])
    }

    // MARK: Paradigm

    @Test("triphasic warns for a race with no profiles of its own, such as 35 km; 80/20 does not")
    func calibrationWarning() async throws {
        let (_, _, viewModel) = try await loaded([race("35K", in: 90, meters: 35_000)])

        viewModel.paradigm = .triphasic
        #expect(viewModel.calibrationWarning != nil)
        viewModel.paradigm = .polarized8020
        #expect(viewModel.calibrationWarning == nil)
    }

    @Test("triphasic does not warn for a 5K, a 10K or a half marathon: they have their own session profiles (MVP5-154)")
    func noCalibrationWarningForShortRaces() async throws {
        for meters in [5_000.0, 10_000, 21_097.5] {
            let (_, _, viewModel) = try await loaded([race("Race", in: 90, meters: meters)])
            viewModel.paradigm = .triphasic
            #expect(viewModel.calibrationWarning == nil, "\(meters)")
        }
    }

    @Test("the macro fills the lead time with base and keeps the paradigm's fixed phases")
    func macroLayout() {
        let triphasic = PlanMacro.template(for: .triphasic, microLengthDays: 7, leadTimeDays: 20 * 7, includeConditioning: false)
        #expect(triphasic.mesoBlocks.map(\.phase) == [.base, .structural, .specific, .taper])
        #expect(triphasic.mesoBlocks.map(\.microCount) == [7, 6, 6, 1])

        let tenDay = PlanMacro.template(for: .triphasic, microLengthDays: 10, leadTimeDays: 200, includeConditioning: false)
        #expect(tenDay.mesoBlocks.first { $0.phase == .structural }?.microCount == 4)
        #expect(tenDay.mesoBlocks.first { $0.phase == .base }?.microCount == 20 - 4 - 4 - 1)

        let conditioned = PlanMacro.template(for: .triphasic, microLengthDays: 7, leadTimeDays: 30 * 7, includeConditioning: true)
        #expect(conditioned.mesoBlocks.map(\.phase) == [.conditioning, .base, .structural, .specific, .taper])

        let polarized = PlanMacro.template(for: .polarized8020, microLengthDays: 7, leadTimeDays: 16 * 7, includeConditioning: false)
        #expect(polarized.mesoBlocks.map(\.phase) == [.base, .build, .peak, .taper])
        #expect(polarized.mesoBlocks.map(\.microCount) == [7, 5, 3, 1])

        let short = PlanMacro.template(for: .triphasic, microLengthDays: 7, leadTimeDays: 5 * 7, includeConditioning: false)
        #expect(short.mesoBlocks.map(\.phase) == [.structural, .specific, .taper])
    }

    // MARK: Peak volume

    @Test("a peak in hours becomes the plan's weekly maximum and the generator's peak")
    func peakInHours() async throws {
        let (_, _, viewModel) = try await loaded([race("Target", in: 120)])
        viewModel.peak = PeakVolumeDraft(measure: .duration, text: "6")

        let request = try #require(viewModel.makeRequest())

        #expect(request.preferences.maxWeeklyVolume[.running] == VolumeTarget(measure: .durationSeconds, amount: 6 * 3600))
        #expect(request.peakVolume.amount == 6 * 3600)
        #expect(viewModel.peakVolumeNote == nil)
        #expect(viewModel.preferences.maxWeeklyVolume.isEmpty)
    }

    @Test("a peak in distance plans in distance: the weekly maximum, the peak and the starting volume are meters")
    func peakInDistance() async throws {
        let (_, _, viewModel) = try await loaded([race("Target", in: 120)])
        viewModel.peak = PeakVolumeDraft(measure: .distance, text: "60", distanceSystem: .metric)

        let request = try #require(viewModel.makeRequest())

        #expect(request.preferences.maxWeeklyVolume[.running] == VolumeTarget(measure: .distanceMeters, amount: 60_000))
        #expect(request.peakVolume == VolumeTarget(measure: .distanceMeters, amount: 60_000))
        #expect(request.startingVolume.measure == .distanceMeters)
        #expect(request.startingVolume.amount <= 60_000)
        #expect(viewModel.peakVolumeNote == nil)
    }

    @Test("a peak in TRIMP is kept but not used, with a note, and an empty one gets the default")
    func peakInTRIMP() async throws {
        let (_, _, viewModel) = try await loaded([race("Target", in: 120)])
        viewModel.peak = PeakVolumeDraft(measure: .trimp, text: "400")

        let request = try #require(viewModel.makeRequest())

        #expect(request.preferences.maxWeeklyVolume.isEmpty)
        #expect(viewModel.peakVolumeNote != nil)
        #expect(request.peakVolume.measure == .durationSeconds)
        #expect(request.peakVolume.amount == request.startingVolume.amount * CreatePlanViewModel.defaultPeakFactor)
        viewModel.peak = PeakVolumeDraft(measure: .duration, text: "")
        #expect(viewModel.peakVolumeNote == nil)
    }

    @Test("the peak field starts in time, not the draft's default TRIMP that the generator does not plan by")
    func peakStartsInTime() async throws {
        let (_, model) = try await makeModel()

        #expect(makeViewModel(model).peak.measure == .duration)
    }

    @Test("an invalid peak blocks its step")
    func invalidPeak() async throws {
        let (_, _, viewModel) = try await loaded([race("Target", in: 120)])
        viewModel.peak = PeakVolumeDraft(measure: .duration, text: "abc")
        #expect(viewModel.problem(in: .peakVolume) != nil)
        viewModel.peak = PeakVolumeDraft(measure: .duration, text: "99")
        #expect(viewModel.problem(in: .peakVolume) != nil)
    }

    @Test("the starting volume is the last four weeks of running averaged, else three hours")
    func startingVolume() async throws {
        let (store, model) = try await makeModel()
        let viewModel = makeViewModel(model)
        #expect(viewModel.startingVolume(asOf: day(0)) == CreatePlanViewModel.fallbackStartingVolume)

        let run = Activity(source: .manual, sport: .running, start: day(-5), duration: 4 * 3600)
        let ride = Activity(source: .manual, sport: .cycling, start: day(-6), duration: 9 * 3600)
        try await store.upsert([run, ride])
        try await model.load(in: day(-30)...day(200), asOf: now)

        #expect(viewModel.startingVolume(asOf: day(0)) == 3600)
    }

    // MARK: Steps

    @Test("the wizard moves forward only past complete steps and back at any time")
    func navigation() async throws {
        let (_, _, viewModel) = try await loaded([race("Target", in: 120)])
        #expect(viewModel.step == .startDate)
        #expect(!viewModel.canGoBack)

        for expected in [CreatePlanStep.races, .paradigm, .preferences, .peakVolume, .review] {
            viewModel.next()
            #expect(viewModel.step == expected)
        }
        viewModel.next()
        #expect(viewModel.step == .review)
        viewModel.back()
        #expect(viewModel.step == .peakVolume)
    }

    @Test("an incomplete step stops next()")
    func nextStopsOnProblem() async throws {
        let (_, model) = try await makeModel()
        let viewModel = makeViewModel(model)
        await viewModel.load()
        viewModel.next()
        #expect(viewModel.step == .races)
        viewModel.next()
        #expect(viewModel.step == .races)
    }

    // MARK: Generate and commit

    @Test("changing the micro length changes the request's meso and hides the proposal")
    func microLengthChange() async throws {
        let (_, _, viewModel) = try await loaded([race("Target", in: 120)])
        #expect(viewModel.makeRequest()?.meso.microLengthDays == 7)
        await viewModel.generate()
        #expect(viewModel.failure == nil)
        #expect(viewModel.proposal != nil)

        viewModel.microLength = 10

        #expect(viewModel.proposal == nil)
        #expect(viewModel.makeRequest()?.meso.microLengthDays == 10)
    }

    @Test("generate builds a proposal the review can read, and the proposal follows the choices")
    func generates() async throws {
        let (_, _, viewModel) = try await loaded([race("Target", in: 120), race("Tune-up", in: 50, .secondary)])
        viewModel.toggle(viewModel.upcomingRaces[0])

        await viewModel.generate()

        let summary = try #require(viewModel.summary)
        #expect(summary.microCount > 10)
        #expect(summary.microLengthDays == 7)
        #expect(summary.workoutCount > 0)
        #expect(!summary.phases.isEmpty)
        viewModel.paradigm = .triphasic
        #expect(viewModel.proposal == nil)
    }

    @Test("sessions that found no place are counted per reason, not listed for every micro-cycle")
    func compromisesAreGrouped() async throws {
        let (_, _, viewModel) = try await loaded([race("Target", in: 120)])
        var oneDay = RunAvailability()
        oneDay[.monday] = [.morning]
        viewModel.setAvailability(oneDay)

        await viewModel.generate()

        let summary = try #require(viewModel.summary)
        let unplaced = summary.compromises.filter { $0.contains("found no place") }
        #expect(unplaced.count <= 2)
        #expect(summary.compromises.count < summary.microCount)
    }

    @Test("recovery days, sizing and unresolved steps are counted per kind, not listed for every micro-cycle")
    func newCompromisesAreGrouped() async throws {
        let (_, _, viewModel) = try await loaded([race("Target", in: 120)])
        await viewModel.generate()
        var proposal = try #require(viewModel.proposal)
        let d1 = Date(timeIntervalSince1970: 1_800_000_000), d2 = d1.addingTimeInterval(10 * 86400)
        proposal.compromises = [
            .recoveryDaysShort(day: d1, template: "Mixed Interval Runs", neededDays: 2, availableDays: 1),
            .recoveryDaysShort(day: d2, template: "Mixed Interval Runs", neededDays: 2, availableDays: 0),
            .sizingMissedZone(microStart: d1, aimed: .training, reached: .recovery),
            .sizingMissedZone(microStart: d2, aimed: .training, reached: .recovery),
            .sizingMissedZone(microStart: d2, aimed: .race, reached: .training),
            .unresolvedStep(microStart: d1, template: "A", reason: .paceOutsideZone(zone: 4, paceZone: 5)),
            .unresolvedStep(microStart: d2, template: "B", reason: .paceOutsideZone(zone: 4, paceZone: 5)),
            .unresolvedPlanTarget(reason: .noRaceTarget),
        ]

        let lines = PlanProposalSummary(proposal, calendar: Calendar(identifier: .gregorian)).compromises

        #expect(lines.count == 5)
        #expect(lines.contains { $0.hasPrefix("2 workouts have fewer recovery days") })
        #expect(lines.contains { $0.hasPrefix("2 micro-cycles end fresher than aimed") })
        #expect(lines.contains { $0.contains("more tired than aimed") })
        #expect(lines.contains { $0.contains("2 micro-cycles, the first of") && $0.contains("no workout in the library has a zone") })
        #expect(lines.contains { $0.contains("the race has no target pace") })
    }

    @Test("a generator failure is reported inline and leaves no proposal")
    func generatorFailure() async throws {
        let failing: PlanGenerating = { _ in throw PlanGeneratorError.leadTime(.leadTimeTooShort(availableMicros: 2, requiredMicros: 8)) }
        let (_, _, viewModel) = try await loaded([race("Target", in: 20)], generator: failing)

        await viewModel.generate()

        #expect(viewModel.proposal == nil)
        #expect(viewModel.failure?.contains("enough time") == true)
        #expect(!viewModel.isGenerating)
        #expect(await viewModel.commit() == nil)
    }

    @Test("a second generate while one runs is ignored")
    func generateDoubleTap() async throws {
        let (_, _, seed) = try await loaded([race("Target", in: 120)])
        let proposal = try await PlanGenerator.generate(try #require(seed.makeRequest()))
        let gate = Gate()
        let counter = Counter()
        let (_, _, viewModel) = try await loaded([race("Target", in: 120)], generator: { _ in
            await counter.bump()
            await gate.wait()
            return proposal
        })

        let first = Task { await viewModel.generate() }
        while await counter.value == 0 { await Task.yield() }
        #expect(viewModel.isGenerating)
        await viewModel.generate()
        #expect(await counter.value == 1)
        #expect(!viewModel.canAdvance)
        await gate.open()
        await first.value

        #expect(!viewModel.isGenerating)
        #expect(await counter.value == 1)
    }

    @Test("a result generated for earlier choices is not shown for later ones")
    func staleResult() async throws {
        let (_, _, seed) = try await loaded([race("Target", in: 120)])
        let proposal = try await PlanGenerator.generate(try #require(seed.makeRequest()))
        let gate = Gate()
        let counter = Counter()
        let (_, _, viewModel) = try await loaded([race("Target", in: 120)], generator: { _ in
            await counter.bump()
            await gate.wait()
            return proposal
        })

        let running = Task { await viewModel.generate() }
        while await counter.value == 0 { await Task.yield() }
        viewModel.microLength = 14
        await gate.open()
        await running.value

        #expect(viewModel.proposal == nil)
    }

    @Test("commit stores a draft, not an active plan, and a second commit does nothing")
    func commitsDraft() async throws {
        let (store, model, viewModel) = try await loaded([race("Target", in: 120)])
        await viewModel.generate()
        let before = model.trainingPlans.count

        let plan = try #require(await viewModel.commit())

        #expect(plan.status == .draft)
        #expect(plan.name == "Target plan")
        #expect(model.trainingPlans.count == before + 1)
        #expect(model.activeTrainingPlan == nil)
        let stored = try await store.plans(in: Date.distantPast...Date.distantFuture).filter { $0.planID == plan.id }
        #expect(stored.count == viewModel.proposal?.candidate.plannedActivities.count)
        #expect(await viewModel.commit() == nil)
        #expect(model.trainingPlans.count == before + 1)
        #expect(viewModel.committedPlan?.id == plan.id)
    }

    @Test("a typed name is used and a blank one falls back to the race")
    func planName() async throws {
        let (_, _, viewModel) = try await loaded([race("Target", in: 120)])
        viewModel.name = "  Spring build  "
        await viewModel.generate()

        let plan = try #require(await viewModel.commit())

        #expect(plan.name == "Spring build")
    }

    @Test("a commit that fails is reported inline and can be tried again")
    func commitFailure() async throws {
        let (_, model) = try await makeModel(trainingPlans: false)
        let seed = makeViewModel(model)
        try await model.stores.raceStore.upsert([race("Target", in: 120)])
        await seed.load()
        await seed.generate()
        #expect(seed.proposal != nil)

        #expect(await seed.commit() == nil)

        #expect(seed.failure?.hasPrefix("Couldn't save the plan") == true)
        #expect(seed.committedPlan == nil)
        #expect(!seed.isCommitting)
    }

    @Test("generate without the earlier steps complete reports the first problem")
    func generateNeedsSteps() async throws {
        let (_, model) = try await makeModel()
        let viewModel = makeViewModel(model)

        await viewModel.generate()

        #expect(viewModel.failure != nil)
        #expect(viewModel.proposal == nil)
    }
}

private actor Counter {
    private(set) var value = 0
    func bump() { value += 1 }
}

private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
