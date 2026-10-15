import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

/// The week view forecasting planned workouts from earlier activities (MVP2-35, MVP2-111). The
/// forecast itself is TrainingKit's and tested there; these check the wiring.
///
/// The athlete has resting 50 / max 190 bpm (zone 2 is 134–148 bpm) and a 300 s/km threshold pace,
/// so zone 2's pace-model speed is 2.78 m/s.
@MainActor
@Suite("WeekViewModel pace history (MVP2-35, MVP2-111)")
struct WeekViewModelPaceHistoryTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func makeViewModel() -> (WeekViewModel, TrainingModel, InMemoryStore) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        let model = TrainingModel(stores: stores, athlete: .fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 190))
        return (WeekViewModel(model: model, refresher: FakeRefresher(), today: day(10)), model, store)
    }

    /// A 40-minute zone-2 run at 3.0 m/s, sampled every 5 s.
    private func easyRun(on start: Date) -> Activity {
        let times = stride(from: 0.0, through: 2400, by: 5).map { start.addingTimeInterval($0) }
        return Activity(
            source: .healthKit(UUID()), sport: .running, start: start, duration: 2400, distanceMeters: 7200,
            heartRate: times.map { HeartRateSample(time: $0, bpm: 141) },
            speed: times.map { SpeedSample(time: $0, metersPerSecond: 3.0) }
        )
    }

    private func easyWorkout() -> StructuredWorkout {
        StructuredWorkout(
            name: "Easy", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(2400), target: .heartRateZone(2))])]
        )
    }

    @Test("the week view reads earlier activities from the store and forecasts planned workouts from them")
    func forecastsFromStore() async throws {
        let (viewModel, model, store) = makeViewModel()
        try await store.upsert([easyRun(on: day(3))])
        let easy = easyWorkout()
        try await model.add(easy, asOf: day(10))
        let plan = PlannedActivity(workoutID: easy.id, date: day(10))
        try await model.add(plan, asOf: day(10))

        let before = viewModel.plannedWorkoutDetailViewModel(for: plan)
        #expect(before.forecastActivityCount == 0)
        #expect(abs((before.expectedDistanceMeters ?? 0) - 2400 / 0.36) < 0.5)
        #expect(before.forecastBasis == "Forecast from your pace model; no similar workouts yet.")

        await viewModel.refreshPaceHistoryIfNeeded(asOf: day(10))

        let after = viewModel.plannedWorkoutDetailViewModel(for: plan)
        #expect(viewModel.paceHistory.activityCount == 1)
        #expect(after.forecastActivityCount == 1)
        #expect((after.expectedDistanceMeters ?? 0) > 2400 * 2.9)
        #expect(after.forecastBasis == "Forecast from your pace in 1 similar workout.")
        // A sheet that was already open reads the new history too.
        #expect(before.forecastActivityCount == 1)
    }

    @Test("a new pace history refreshes the week's planned totals")
    func statsPagesFollowTheHistory() async throws {
        let (viewModel, model, store) = makeViewModel()
        try await store.upsert([easyRun(on: day(3))])
        let easy = easyWorkout()
        try await model.add(easy, asOf: day(10))
        try await model.add(PlannedActivity(workoutID: easy.id, date: day(10)), asOf: day(10))
        let weekStart = viewModel.displayedWeekStart

        let before = try #require(viewModel.sportStatsPages(for: weekStart, asOf: day(10)).first)
        await viewModel.refreshPaceHistoryIfNeeded(asOf: day(10))
        let after = try #require(viewModel.sportStatsPages(for: weekStart, asOf: day(10)).first)

        #expect(abs(before.plannedDistanceMeters - 2400 / 0.36) < 0.5)
        #expect(after.plannedDistanceMeters > 2400 * 2.9)
    }

    // MARK: - When the history is re-read

    @Test("moving to another week doesn't re-read the history; an import does")
    func navigationDoesNotReread() async throws {
        let (viewModel, _, store) = makeViewModel()
        try await store.upsert([easyRun(on: day(3))])
        await viewModel.load(asOf: day(10))
        #expect(viewModel.paceHistory.activityCount == 1)
        let generation = viewModel.paceHistoryGeneration

        // Stored behind the week view's back: only a re-read would find it.
        try await store.upsert([easyRun(on: day(4))])
        viewModel.goToPreviousWeek()
        await viewModel.load(asOf: day(10))

        #expect(viewModel.paceHistory.activityCount == 1)
        #expect(viewModel.paceHistoryGeneration == generation)

        await viewModel.refresh(asOf: day(10))

        #expect(viewModel.paceHistory.activityCount == 2)
        #expect(viewModel.paceHistoryGeneration == generation + 1)
    }

    @Test("re-reading an unchanged history leaves the cached cards and stats alone")
    func unchangedHistoryKeepsCaches() async throws {
        let (viewModel, _, store) = makeViewModel()
        try await store.upsert([easyRun(on: day(3))])
        await viewModel.refreshPaceHistoryIfNeeded(asOf: day(10), force: true)
        let generation = viewModel.paceHistoryGeneration

        await viewModel.refreshPaceHistoryIfNeeded(asOf: day(10), force: true)

        #expect(generation == 1)
        #expect(viewModel.paceHistoryGeneration == generation)
    }

    @Test("a failed read keeps the previous history and is retried on the next refresh")
    func failedReadIsRetried() async throws {
        let base = InMemoryStore()
        let failing = FailingActivityStore(base: base)
        let stores = StoreSet(
            activityStore: failing, planStore: base, workoutStore: base,
            cycleStore: base, raceStore: base, athleteStore: base
        )
        let model = TrainingModel(stores: stores, athlete: .fixture(restingHeartRateBPM: 50, maxHeartRateBPM: 190))
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(10))
        try await base.upsert([easyRun(on: day(3))])
        await failing.setFailsRangeReads(true)

        await viewModel.refreshPaceHistoryIfNeeded(asOf: day(10))

        #expect(viewModel.paceHistory.activityCount == 0)
        #expect(viewModel.paceHistoryGeneration == 0)

        await failing.setFailsRangeReads(false)
        // Not forced: the failed read left the key unset, so this reads again.
        await viewModel.refreshPaceHistoryIfNeeded(asOf: day(10))

        #expect(viewModel.paceHistory.activityCount == 1)
    }

    // MARK: - What uses it

    @Test("a linked activity's planned values aren't forecast from that activity itself")
    func linkedExpectationExcludesItsOwnActivity() async throws {
        let (viewModel, model, store) = makeViewModel()
        let easy = easyWorkout()
        try await model.add(easy, asOf: day(10))
        let plan = PlannedActivity(workoutID: easy.id, date: day(3))
        try await model.add(plan, asOf: day(10))
        var run = easyRun(on: day(3))
        run.linkedPlanID = plan.id
        try await store.upsert([run])
        await viewModel.refreshPaceHistoryIfNeeded(asOf: day(10))
        #expect(viewModel.paceHistory.activityCount == 1)

        let expectation = try #require(viewModel.linkedPlanExpectation(for: run))

        // Its own 3.0 m/s run is the only one in the history, so the pace model's figure stands.
        #expect(abs((expectation.distanceMeters ?? 0) - 2400 / 0.36) < 0.5)
    }

    @Test("a planned card with a distance step shows the duration forecast from the history")
    func plannedCardDurationFollowsTheHistory() async throws {
        let (viewModel, model, store) = makeViewModel()
        try await store.upsert([easyRun(on: day(3))])
        let mixed = StructuredWorkout(
            name: "Warm-up and 5 km", sport: .running,
            blocks: [
                WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(600), target: .heartRateZone(2))]),
                WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .distance(5000), target: .heartRateZone(2))])
            ]
        )
        try await model.add(mixed, asOf: day(10))
        let plan = PlannedActivity(workoutID: mixed.id, date: day(10))
        try await model.add(plan, asOf: day(10))

        guard case .duration(let before)? = viewModel.plannedCardSummary(for: plan).extent else {
            Issue.record("expected a duration extent")
            return
        }
        await viewModel.refreshPaceHistoryIfNeeded(asOf: day(10))
        guard case .duration(let after)? = viewModel.plannedCardSummary(for: plan).extent else {
            Issue.record("expected a duration extent")
            return
        }

        // The pace model's 2.78 m/s makes 5 km 1800 s; the earlier 3.0 m/s run makes it about 1670 s.
        #expect(abs(before - 2400) < 1e-6)
        #expect(after < 2350)
    }

    @Test("the detail sheet labels a duration as a forecast only when distance or open steps make it one")
    func durationForecastLabel() async throws {
        let (viewModel, model, _) = makeViewModel()
        func detail(_ steps: [WorkoutStep]) async throws -> PlannedWorkoutDetailViewModel {
            let workout = StructuredWorkout(name: "W", sport: .running, blocks: [WorkoutBlock(steps: steps)])
            try await model.add(workout, asOf: day(10))
            let plan = PlannedActivity(workoutID: workout.id, date: day(10))
            try await model.add(plan, asOf: day(10))
            return viewModel.plannedWorkoutDetailViewModel(for: plan)
        }

        let timed = try await detail([WorkoutStep(kind: .work, goal: .time(1200), target: .heartRateZone(2))])
        let distance = try await detail([WorkoutStep(kind: .work, goal: .distance(5000), target: .heartRateZone(2))])
        let open = try await detail([WorkoutStep(kind: .work, goal: .open, target: .heartRateZone(2))])

        #expect(!timed.isDurationForecast)
        #expect(timed.isDistanceForecast)
        #expect(distance.isDurationForecast)
        #expect(!distance.isDistanceForecast)
        #expect(open.isDurationForecast)
        #expect(open.isDistanceForecast)
    }

    @Test("the forecast footnote says how many earlier workouts it came from")
    func forecastBasisWording() {
        func basis(count: Int, durationForecast: Bool = true, distanceForecast: Bool = false) -> String? {
            PlannedWorkoutDetailViewModel.Expected(
                duration: 1200, distanceMeters: 4000, isDurationForecast: durationForecast,
                isDistanceForecast: distanceForecast, activityCount: count
            ).basis
        }

        #expect(basis(count: 0) == "Forecast from your pace model; no similar workouts yet.")
        #expect(basis(count: 1) == "Forecast from your pace in 1 similar workout.")
        #expect(basis(count: 3) == "Forecast from your paces in 3 similar workouts.")
        #expect(basis(count: 3, durationForecast: false, distanceForecast: true) != nil)
        #expect(basis(count: 3, durationForecast: false) == nil)
    }
}
