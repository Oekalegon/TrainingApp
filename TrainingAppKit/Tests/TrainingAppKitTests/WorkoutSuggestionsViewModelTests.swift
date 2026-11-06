import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

/// MVP5-156: the ranked list of workouts for a day.
@MainActor
@Suite("WorkoutSuggestionsViewModel")
struct WorkoutSuggestionsViewModelTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func day(_ offset: Int) -> Date { now.addingTimeInterval(Double(offset) * 86_400) }

    private func makeModel() async throws -> (InMemoryStore, TrainingModel) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store, cycleStore: store, raceStore: store, athleteStore: store
        )
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC", restingHeartRateBPM: 50, maxHeartRateBPM: 190)
        try await store.save(athlete)
        return (store, TrainingModel(stores: stores, athlete: athlete))
    }

    /// A ranked workout from `template` at its defaults.
    private func ranked(
        _ template: WorkoutTemplate, values override: [String: Double] = [:], tsb: Double? = -8, microSeconds: TimeInterval? = 18_000,
        reasons: [WorkoutRankReason] = []
    ) throws -> RankedWorkout {
        var values = Dictionary(uniqueKeysWithValues: template.parameters.map { ($0.key, $0.defaultValue) })
        values.merge(override) { _, new in new }
        let workout = try template.instantiate(name: template.name, venue: nil, values: values)
        return RankedWorkout(
            template: template, values: values, workout: workout, seconds: 2_700, load: 41.6, endOfMicroTSB: tsb,
            microSeconds: microSeconds, reasons: reasons
        )
    }

    private func hourWorkout() -> StructuredWorkout {
        StructuredWorkout(
            name: "Steady", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(3600), target: .heartRateZone(2))])]
        )
    }

    @Test("the ranking is shown in order, with the size, the effects and the reasons in words")
    func rowsAndText() async throws {
        let (_, model) = try await makeModel()
        let best = try ranked(BuiltInWorkoutTemplates.easyRun)
        let worst = try ranked(
            BuiltInWorkoutTemplates.tempoRun, tsb: -31,
            reasons: [
                .addsRisk(rule: .monotony, day: day(3)), .recoveryDaysShort(neededDays: 2, availableDays: 1),
                .notAskedInPhase(.base), .aboveMicroVolume(by: 1_500),
            ]
        )
        let viewModel = WorkoutSuggestionsViewModel(model: model, day: day(2), ranking: { _ in [best, worst] }, now: { [now] in now })
        viewModel.distanceSystem = .metric

        await viewModel.load()

        #expect(viewModel.phase == .ranked)
        #expect(viewModel.rows.map(\.title) == ["40min Easy Run", viewModel.rows[1].title])
        #expect(viewModel.rows[1].title.contains("Tempo"))
        let first = viewModel.rows[0]
        #expect(first.detail == "45 min · load 42")
        #expect(first.effects == ["Form at the end of the micro-cycle: -8", "Micro-cycle time: 5 h"])
        #expect(first.reasons.isEmpty)
        let reasons = viewModel.rows[1].reasons
        #expect(reasons.count == 4)
        #expect(reasons[0].hasPrefix("Adds a monotony risk from "))
        #expect(reasons[1] == "Wants 2 days free around it; 1 left.")
        #expect(reasons[2] == "A base micro-cycle doesn't ask for this kind of session.")
        #expect(reasons[3] == "25 min over the micro-cycle's planned time.")
    }

    @Test("the search narrows the list by name and keeps the order")
    func search() async throws {
        let (_, model) = try await makeModel()
        let rows = try [BuiltInWorkoutTemplates.easyRun, BuiltInWorkoutTemplates.tempoRun, BuiltInWorkoutTemplates.longRun].map { try ranked($0) }
        let viewModel = WorkoutSuggestionsViewModel(model: model, day: day(2), ranking: { _ in rows }, now: { [now] in now })
        viewModel.distanceSystem = .metric
        await viewModel.load()

        viewModel.searchText = "tempo"
        #expect(viewModel.filteredRows.count == 1)
        #expect(viewModel.filteredRows.first?.ranked.template.id == BuiltInWorkoutTemplates.tempoRun.id)
        viewModel.searchText = "RUN"
        #expect(viewModel.filteredRows.count == 3)
        viewModel.searchText = "zzz"
        #expect(viewModel.filteredRows.isEmpty)
        viewModel.searchText = "  "
        #expect(viewModel.filteredRows.count == 3)
    }

    @Test("a failing ranking is reported and leaves no rows")
    func failure() async throws {
        struct Boom: Error {}
        let (_, model) = try await makeModel()
        let viewModel = WorkoutSuggestionsViewModel(model: model, day: day(2), ranking: { _ in throw Boom() }, now: { [now] in now })

        await viewModel.load()

        guard case .failed(let message) = viewModel.phase else { Issue.record("not failed"); return }
        #expect(message.hasPrefix("Couldn't rank the workouts"))
        #expect(viewModel.rows.isEmpty)
    }

    @Test("closing the sheet cancels the ranking, and a second load while one runs does nothing")
    func cancellation() async throws {
        let (_, model) = try await makeModel()
        let viewModel = WorkoutSuggestionsViewModel(
            model: model, day: day(2),
            ranking: { _ in
                try await Task.sleep(for: .seconds(30))
                return []
            },
            now: { [now] in now }
        )

        let task = Task { await viewModel.load() }
        while viewModel.phase != .ranking { await Task.yield() }
        await viewModel.load()   // ignored: one is running
        #expect(viewModel.phase == .ranking)

        task.cancel()
        await task.value

        #expect(viewModel.phase == .idle)
        #expect(viewModel.rows.isEmpty)
    }

    @Test("the ranking is given the day, the plan being replaced and the micro-cycle's typical time")
    func input() async throws {
        let (store, model) = try await makeModel()
        let steady = hourWorkout()
        try await store.upsert([steady])
        let old = PlannedActivity(workoutID: steady.id, date: day(2))
        try await store.upsert([old])
        try await model.load(in: day(-30)...day(60), asOf: now)
        let box = InputBox()
        let viewModel = WorkoutSuggestionsViewModel(
            model: model, day: day(2), replacing: old, ranking: { await box.set($0); return [] }, now: { [now] in now }
        )

        await viewModel.load()

        let seen = try #require(await box.value)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(seen.day == calendar.startOfDay(for: day(2)))   // the start of the athlete's day
        #expect(seen.replacing?.id == old.id)
        #expect(seen.plan.map(\.id) == [old.id])
        #expect(seen.templates.count == model.libraryTemplates.count)
        #expect(seen.microSeconds == nil)   // no micro-cycle to compare with
        #expect(viewModel.replacedName == "Steady")
        #expect(!viewModel.isUntargeted)    // replacing is aimed at the old workout's load
    }

    @Test("adding without a typical micro-cycle is ranked without a target, and says so")
    func untargeted() async throws {
        let (_, model) = try await makeModel()
        let viewModel = WorkoutSuggestionsViewModel(model: model, day: day(2), ranking: { _ in [] }, now: { [now] in now })
        await viewModel.load()
        #expect(viewModel.isUntargeted)
    }

    /// Micro-cycles `m0` (0-6), `m1` (7-13), the day's `target` (14-20), a recovery one and a peak one, with 2 h and 4 h
    /// of workouts in the first two and 3 h in the target.
    private func addMicros(_ model: TrainingModel, store: InMemoryStore, targetHours: Int) async throws {
        let steady = hourWorkout()
        try await store.upsert([steady])
        func micro(_ start: Int, _ phase: CyclePhase, _ role: MicroLoadRole) -> TrainingCycle {
            TrainingCycle(level: .micro, phase: phase, loadRole: role, name: "m\(start)", dateRange: day(start)...day(start + 6))
        }
        try await model.add([micro(0, .base, .build), micro(7, .base, .build), micro(14, .base, .build), micro(21, .base, .recovery), micro(28, .peak, .build)])
        // 2 h in the first, 4 h in the second (the median is 3 h), 9 h in a micro-cycle of another role and 9 h of another phase.
        for offset in [0, 1, 7, 8, 9, 10] { try await model.add(PlannedActivity(workoutID: steady.id, date: day(offset)), asOf: day(-30)) }
        for offset in 14..<(14 + targetHours) { try await model.add(PlannedActivity(workoutID: steady.id, date: day(offset)), asOf: day(-30)) }
        for offset in 21...32 { try await model.add(PlannedActivity(workoutID: steady.id, date: day(offset)), asOf: day(-30)) }
    }

    @Test("the typical micro-cycle time is the median of the other micro-cycles of the same phase and role, and what the day's has")
    func microTimes() async throws {
        let (store, model) = try await makeModel()
        try await addMicros(model, store: store, targetHours: 1)
        try await model.load(in: day(-30)...day(60), asOf: day(-30))
        let viewModel = WorkoutSuggestionsViewModel(model: model, day: day(16), ranking: { _ in [] }, now: { [now] in now })

        let times = try #require(await viewModel.microTimes(on: day(16)))

        #expect(times.typical == 10_800.0)
        #expect(times.planned == 3_600.0)
        #expect(times.remaining == 7_200.0)
        let outside = try await viewModel.microTimes(on: day(100))
        #expect(outside == nil)   // no micro-cycle holds the day
        let alone = try await viewModel.microTimes(on: day(29))
        #expect(alone?.typical == nil)   // alone in its phase
    }

    @Test("a micro-cycle partly outside the calendar's loaded window still counts in full")
    func microTimesReadTheStore() async throws {
        let (store, model) = try await makeModel()
        try await addMicros(model, store: store, targetHours: 1)
        try await model.load(in: day(12)...day(20), asOf: day(-30))   // the first two micro-cycles are not loaded
        #expect(!model.plans.contains { $0.date < day(12) })
        let viewModel = WorkoutSuggestionsViewModel(model: model, day: day(16), ranking: { _ in [] }, now: { [now] in now })

        let times = try await viewModel.microTimes(on: day(16))
        #expect(times?.typical == 10_800.0)
    }

    @Test("a micro-cycle that already has its typical time planned ranks everything, and says so")
    func fullMicroCycle() async throws {
        let (store, model) = try await makeModel()
        try await addMicros(model, store: store, targetHours: 4)
        try await model.load(in: day(-30)...day(60), asOf: day(-30))
        let viewModel = WorkoutSuggestionsViewModel(model: model, day: day(16), ranking: { _ in [] }, now: { [now] in now })

        await viewModel.load()

        #expect(viewModel.microTarget == 10_800.0)
        #expect(viewModel.microRemaining == -3_600.0)
        #expect(viewModel.isUntargeted)
        #expect(viewModel.rankingMessage.contains("already has its usual time planned"))
    }

    @Test("a micro-cycle with room is aimed at the time left")
    func roomLeft() async throws {
        let (store, model) = try await makeModel()
        try await addMicros(model, store: store, targetHours: 1)
        try await model.load(in: day(-30)...day(60), asOf: day(-30))
        let viewModel = WorkoutSuggestionsViewModel(model: model, day: day(16), ranking: { _ in [] }, now: { [now] in now })

        await viewModel.load()

        #expect(viewModel.microRemaining == 7_200.0)
        #expect(!viewModel.isUntargeted)
        #expect(viewModel.rankingMessage == "Ranking the workouts")
    }

    @Test("the ranking is given 180 days of history from the store, not only what the calendar loaded")
    func historyFromTheStore() async throws {
        let (store, model) = try await makeModel()
        let old = Activity(source: .manual, sport: .running, start: day(-100), duration: 3600)
        let recent = Activity(source: .manual, sport: .running, start: day(-3), duration: 1800)
        let tooOld = Activity(source: .manual, sport: .running, start: day(-300), duration: 3600)
        try await store.upsert([old, recent, tooOld])
        try await model.load(in: day(-10)...day(10), asOf: now)
        #expect(model.activities.map(\.id) == [recent.id])   // the calendar loaded only a short window
        let box = InputBox()
        let viewModel = WorkoutSuggestionsViewModel(
            model: model, day: day(2), ranking: { await box.set($0); return [] }, now: { [now] in now }
        )

        await viewModel.load()

        let seen = try #require(await box.value)
        #expect(Set(seen.activities.map(\.id)) == [old.id, recent.id])
    }

    @Test("a finished ranking is not run again by a second load, and a failed one is")
    func loadsOnce() async throws {
        struct Boom: Error {}
        let (_, model) = try await makeModel()
        let counter = Counter()
        let fails = FailFlag()
        let viewModel = WorkoutSuggestionsViewModel(
            model: model, day: day(2),
            ranking: { _ in
                await counter.increment()
                if await fails.value { throw Boom() }
                return []
            },
            now: { [now] in now }
        )

        await viewModel.load()
        await viewModel.load()
        #expect(await counter.count == 1)

        let failing = WorkoutSuggestionsViewModel(
            model: model, day: day(2),
            ranking: { _ in
                await counter.increment()
                throw Boom()
            },
            now: { [now] in now }
        )
        await failing.load()
        await failing.load()   // a failed ranking can be tried again
        #expect(await counter.count == 3)
    }

    @Test("variants of one template have titles that tell them apart")
    func variantTitles() async throws {
        let (_, model) = try await makeModel()
        let short = try ranked(BuiltInWorkoutTemplates.easyRun, values: ["duration": 30 * 60])
        let long = try ranked(BuiltInWorkoutTemplates.easyRun, values: ["duration": 45 * 60])
        let viewModel = WorkoutSuggestionsViewModel(model: model, day: day(2), ranking: { _ in [short, long] }, now: { [now] in now })
        viewModel.distanceSystem = .metric

        await viewModel.load()

        #expect(viewModel.rows.map(\.title) == ["40min Easy Run", "55min Easy Run"])
        viewModel.searchText = "55min"
        #expect(viewModel.filteredRows.count == 1)
    }

    @Test("the real ranker orders the workouts of one template for a replaced plan and returns only that template")
    func realRanker() async throws {
        let (_, model) = try await makeModel()
        let template = BuiltInWorkoutTemplates.easyRun
        let old = try template.instantiate(values: ["duration": 30 * 60])
        let plan = PlannedActivity(workoutID: old.id, date: day(2))
        let input = WorkoutRankingInput(
            day: day(2), replacing: plan, plan: [plan], workouts: [old], templates: [template], cycles: [], activities: [],
            races: [], athlete: model.athlete, microSeconds: nil, today: day(0)
        )

        let result = try await input.rank()

        #expect(!result.isEmpty)
        #expect(result.allSatisfy { $0.template.id == template.id })
        #expect(Set(result.map(\.id)).count == result.count)
        let duration = try #require(template.parameters.first { $0.key == "duration" })
        #expect(result.allSatisfy { ($0.values["duration"] ?? 0) >= duration.sliderRange.lowerBound })
        // Aimed at the replaced workout's load: the best fit is not the longest run in the range.
        #expect((result.first?.values["duration"] ?? .infinity) < duration.sliderRange.upperBound)
    }

    @Test("minutes are written as minutes, whole hours as hours and the rest as both")
    func durationText() {
        #expect(WorkoutSuggestionsViewModel.duration(0) == "0 min")
        #expect(WorkoutSuggestionsViewModel.duration(2_700) == "45 min")
        #expect(WorkoutSuggestionsViewModel.duration(3_600) == "1 h")
        #expect(WorkoutSuggestionsViewModel.duration(4_800) == "1 h 20 min")
    }
}

/// Counts the calls of a stubbed ranking, across the actor boundary.
private actor Counter {
    private(set) var count = 0
    func increment() { count += 1 }
}

private actor FailFlag {
    let value = false
}

/// Holds the input a stubbed ranking was given, across the actor boundary.
private actor InputBox {
    private(set) var value: WorkoutRankingInput?
    func set(_ input: WorkoutRankingInput) { value = input }
}
