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
        #expect(before.forecastBasis == "Forecast from your threshold pace; no similar workouts yet.")

        await viewModel.refreshPaceHistoryIfNeeded(asOf: day(10))

        let after = viewModel.plannedWorkoutDetailViewModel(for: plan)
        #expect(viewModel.paceHistory.activityCount == 1)
        #expect(after.forecastActivityCount == 1)
        #expect((after.expectedDistanceMeters ?? 0) > 2400 * 2.9)
        #expect(after.forecastBasis == "Forecast from your pace in 1 similar workout.")
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
}
