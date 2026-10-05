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
        #expect(await viewModel.openActivity(id: ride.id)?.id == ride.id)
        #expect(viewModel.activityError == nil)
        #expect(viewModel.loadError == nil)
    }

    @Test("opening a missing activity reports it, and the alert clears it")
    func missingActivityReportsError() async {
        let (_, model) = await makeModel()
        let viewModel = makeViewModel(model: model)

        #expect(await viewModel.openActivity(id: UUID()) == nil)
        #expect(viewModel.activityError != nil)
        #expect(!viewModel.isOpening)

        viewModel.clearActivityError()
        #expect(viewModel.activityError == nil)
    }

    @Test("a store that can't be read reports a load error and keeps no results")
    func reloadFailureReportsError() async throws {
        let store = InMemoryStore()
        let failing = FailingActivityStore(base: store)
        let stores = StoreSet(
            activityStore: failing, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        let model = TrainingModel(stores: stores, athlete: AthleteProfile.fixture(timeZoneIdentifier: "UTC"))
        try await store.upsert([Activity(source: .manual, sport: .cycling, start: day(0), duration: 3600)])
        await failing.setFailsRangeReads(true)
        let viewModel = makeViewModel(model: model)

        await viewModel.reload()

        #expect(viewModel.loadError != nil)
        #expect(viewModel.results(for: "cycling", asOf: day(0)).activities.isEmpty)

        await failing.setFailsRangeReads(false)
        await viewModel.reload()
        #expect(viewModel.loadError == nil)
        #expect(viewModel.results(for: "cycling", asOf: day(0)).activities.count == 1)
    }

    @Test("a plan is done, missed or upcoming by the week view's rule")
    func planStatus() async throws {
        let (store, model) = await makeModel()
        let workout = try BuiltInWorkoutTemplates.easyRun.instantiate(name: "Status run")
        try await store.upsert([workout])
        let missed = PlannedActivity(workoutID: workout.id, date: day(-3))
        let done = PlannedActivity(workoutID: workout.id, date: day(-2), completedActivityID: UUID())
        let dueToday = PlannedActivity(workoutID: workout.id, date: day(0))
        let upcoming = PlannedActivity(workoutID: workout.id, date: day(4))
        try await store.upsert([missed, done, dueToday, upcoming])
        let viewModel = makeViewModel(model: model)
        await viewModel.reload()

        let plans = viewModel.results(for: "status run", asOf: day(0)).plans
        let statuses = Dictionary(uniqueKeysWithValues: plans.map { ($0.id, viewModel.status(of: $0, asOf: day(0))) })
        #expect(statuses[missed.id] == .missed)
        #expect(statuses[done.id] == .done)
        #expect(statuses[dueToday.id] == .upcoming)
        #expect(statuses[upcoming.id] == .upcoming)
    }

    @Test("a plan's date matches as written in the athlete's timezone")
    func matchesDates() async throws {
        let (store, model) = await makeModel()
        let workout = try BuiltInWorkoutTemplates.easyRun.instantiate(name: "Dated run")
        try await store.upsert([workout])
        let plan = PlannedActivity(workoutID: workout.id, date: day(1))
        try await store.upsert([plan])
        let viewModel = makeViewModel(model: model)
        await viewModel.reload()

        // Written with the same formatter family the results use, so the test holds in any locale.
        var monthFormat = Date.FormatStyle.dateTime.month(.wide)
        monthFormat.timeZone = TimeZone(identifier: "UTC")!
        var yearFormat = Date.FormatStyle.dateTime.year()
        yearFormat.timeZone = TimeZone(identifier: "UTC")!
        let query = "\(day(1).formatted(monthFormat)) \(day(1).formatted(yearFormat))"

        #expect(viewModel.results(for: query, asOf: day(0)).plans.map(\.id) == [plan.id])
    }

    @Test("closing a sheet reloads only after something changed")
    func reloadIfChangedOnlyAfterChange() async throws {
        let (store, model) = await makeModel()
        let viewModel = makeViewModel(model: model)
        await viewModel.reload()
        try await store.upsert([Activity(source: .manual, sport: .cycling, start: day(0), duration: 3600)])

        await viewModel.reloadIfChanged()
        #expect(viewModel.results(for: "cycling", asOf: day(0)).activities.isEmpty)

        viewModel.markChanged()
        await viewModel.reloadIfChanged()
        #expect(viewModel.results(for: "cycling", asOf: day(0)).activities.count == 1)
    }

    // MARK: Opening results outside the week view's window

    private func makeWeekViewModel() async -> (InMemoryStore, WeekViewModel, SearchViewModel) {
        let (store, model) = await makeModel()
        let week = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        await week.load(asOf: day(0))
        return (store, week, week.searchViewModel(library: week.workoutLibraryViewModel()))
    }

    @Test("a plan opened from search far from the displayed week follows an edit in its sheet")
    func openPlanOutsideWindow() async throws {
        let (store, week, search) = await makeWeekViewModel()
        let workout = try BuiltInWorkoutTemplates.easyRun.instantiate(name: "Far away run")
        try await store.upsert([workout])
        let plan = PlannedActivity(workoutID: workout.id, date: day(70))
        try await store.upsert([plan])
        await search.reload()
        let result = try #require(search.results(for: "far away", asOf: day(0)).plans.first)

        let opened = try #require(await search.open(result))
        let detail = week.plannedWorkoutDetailViewModel(for: opened, asOf: day(0))

        #expect(!detail.isDeleted)
        #expect(detail.workout?.id == workout.id)
        let editor = detail.makeEditor()
        editor.loadOverride = 90
        #expect(await editor.save(asOf: day(0)))
        #expect(detail.plan.expectedLoadOverride == 90)
    }

    @Test("an activity opened from search far from the displayed week shows its plan link")
    func openActivityOutsideWindow() async throws {
        let (store, week, search) = await makeWeekViewModel()
        let workout = try BuiltInWorkoutTemplates.easyRun.instantiate(name: "Linked far run")
        try await store.upsert([workout])
        let activityID = UUID()
        let plan = PlannedActivity(workoutID: workout.id, date: day(70), completedActivityID: activityID)
        try await store.upsert([plan])
        try await store.upsert([Activity(
            id: activityID, source: .manual, sport: .running, start: day(70), duration: 2400, linkedPlanID: plan.id
        )])
        await search.reload()
        let result = try #require(search.results(for: "linked far", asOf: day(0)).activities.first)

        let opened = try #require(await search.openActivity(id: result.id))

        #expect(week.planLinkContext(for: opened)?.linkedPlan != nil)
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
