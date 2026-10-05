import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@MainActor
@Suite("SearchViewModel")
struct SearchViewModelTests {
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

    private func makeViewModel(model: TrainingModel) -> SearchViewModel {
        let library = WorkoutLibraryViewModel(model: model, scheduler: { nil })
        library.distanceSystem = .metric
        return SearchViewModel(model: model, library: library)
    }

    @Test("a blank query finds nothing")
    func blankQueryIsEmpty() async throws {
        let (store, model) = await makeModel()
        try await store.upsert([Activity(source: .manual, sport: .running, start: day(0), duration: 1800)])
        let viewModel = makeViewModel(model: model)
        await viewModel.reload()

        #expect(viewModel.results(for: "", asOf: day(0)).isEmpty)
        #expect(viewModel.results(for: "   ", asOf: day(0)).isEmpty)
    }

    @Test("finds templates, planned workouts and activities together, newest first")
    func findsEveryKind() async throws {
        let (store, model) = await makeModel()
        let tempo = try BuiltInWorkoutTemplates.tempoRun.instantiate(name: "Thursday tempo")
        try await store.upsert([tempo])
        let older = PlannedActivity(workoutID: tempo.id, date: day(1))
        let newer = PlannedActivity(workoutID: tempo.id, date: day(8))
        try await store.upsert([older, newer])
        let linked = Activity(source: .manual, sport: .running, start: day(1), duration: 2400, linkedPlanID: older.id)
        let ride = Activity(source: .manual, sport: .cycling, start: day(2), duration: 3600, distanceMeters: 30_000)
        try await store.upsert([linked, ride])
        let viewModel = makeViewModel(model: model)
        await viewModel.reload()

        let tempoResults = viewModel.results(for: "TEMPO", asOf: day(0))
        #expect(tempoResults.templates.map(\.id) == [BuiltInWorkoutTemplates.tempoRun.id])
        #expect(tempoResults.plans.map(\.id) == [newer.id, older.id])
        #expect(tempoResults.plans.first?.name == "Thursday tempo")
        // An activity matches on the name of the plan it's linked to.
        #expect(tempoResults.activities.map(\.id) == [linked.id])
        #expect(tempoResults.activities.first?.planName == "Thursday tempo")

        // By sport, across all three kinds.
        let cycling = viewModel.results(for: "cycling", asOf: day(0))
        #expect(cycling.templates.isEmpty)
        #expect(cycling.plans.isEmpty)
        #expect(cycling.activities.map(\.id) == [ride.id])

        let running = viewModel.results(for: "running", asOf: day(0))
        #expect(running.activities.map(\.id) == [linked.id])
        #expect(running.plans.count == 2)

        #expect(viewModel.results(for: "swim", asOf: day(0)).isEmpty)
    }

    @Test("a planned workout links to its done state, and a missing workout still shows the plan")
    func planDetails() async throws {
        let (store, model) = await makeModel()
        let easy = try BuiltInWorkoutTemplates.easyRun.instantiate(name: "Easy one")
        try await store.upsert([easy])
        let done = PlannedActivity(workoutID: easy.id, date: day(1), completedActivityID: UUID())
        let orphan = PlannedActivity(workoutID: UUID(), date: day(2))
        try await store.upsert([done, orphan])
        let viewModel = makeViewModel(model: model)
        await viewModel.reload()

        #expect(viewModel.results(for: "easy one", asOf: day(0)).plans.map(\.isDone) == [true])
        let orphanResult = viewModel.results(for: "planned workout", asOf: day(0)).plans
        #expect(orphanResult.map(\.id) == [orphan.id])
        #expect(orphanResult.first?.sport == nil)
    }

    @Test("results follow a reload, and activity(id:) returns the full activity")
    func reloadAndFetch() async throws {
        let (store, model) = await makeModel()
        let viewModel = makeViewModel(model: model)
        await viewModel.reload()
        #expect(viewModel.results(for: "cycling", asOf: day(0)).activities.isEmpty)

        let ride = Activity(source: .manual, sport: .cycling, start: day(2), duration: 3600)
        try await store.upsert([ride])
        await viewModel.reload()

        #expect(viewModel.results(for: "cycling", asOf: day(0)).activities.map(\.id) == [ride.id])
        #expect(await viewModel.activity(id: ride.id)?.id == ride.id)
        #expect(await viewModel.activity(id: UUID()) == nil)
        #expect(viewModel.loadError == nil)
    }

    @Test("a query matches only when every word matches some field")
    func queryNeedsEveryWord() {
        let query = SearchQuery("  long   KM ")
        #expect(query.words == ["long", "KM"])
        #expect(query.matches(["20 km Long Run"]))
        #expect(query.matches(["Long run", "20 km"]))
        #expect(!query.matches(["Long run"]))
        #expect(SearchQuery("").isEmpty)
        #expect(SearchQuery("café").matches(["Cafe ride"]))
    }
}
