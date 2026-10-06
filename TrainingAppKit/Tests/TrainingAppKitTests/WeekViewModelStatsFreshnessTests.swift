import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

/// MVP2-54: every stats figure (stats bar, daily-load chart, CTL/ATL/TSB pills) reflects an added,
/// deleted or changed activity or plan straight away, without the athlete switching weeks — and
/// a missed planned workout never counts anywhere.
@MainActor
@Suite("WeekViewModel stats freshness")
struct WeekViewModelStatsFreshnessTests {
    private struct Importer: ActivityImporting {
        let activities: [Activity]
        func importActivities(since anchor: ImportAnchor?) async throws -> ImportResult {
            ImportResult(upserted: activities, deletedSources: [], anchor: nil)
        }
    }

    private struct Fixture {
        let store: InMemoryStore
        let model: TrainingModel
        let viewModel: WeekViewModel
        /// The displayed week's first day, used as "today" so the day-after is still in the week.
        let today: Date
        var tomorrow: Date { today.addingTimeInterval(86400) }
    }

    private func makeFixture(importing activities: (Date) -> [Activity] = { _ in [] }) async -> Fixture {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC", restingHeartRateBPM: 50, maxHeartRateBPM: 190)
        let model = TrainingModel(stores: stores, athlete: athlete)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let probe = WeekViewModel(model: model, refresher: FakeRefresher(), today: now)
        let today = probe.displayedWeekStart
        let refresher = ImportingRefresher(model: model, importer: Importer(activities: activities(today)))
        let viewModel = WeekViewModel(model: model, refresher: refresher, today: now)
        await viewModel.load(asOf: today)
        return Fixture(store: store, model: model, viewModel: viewModel, today: today)
    }

    private func easyRun() -> StructuredWorkout {
        StructuredWorkout(
            name: "Easy Run", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800), target: .heartRateZone(2))])]
        )
    }

    private func runningPage(_ f: Fixture) -> SportStatsPage? {
        f.viewModel.sportStatsPages(asOf: f.today).first { $0.sport == .running }
    }

    @Test("an imported activity shows in the stats, the load chart and the day's pills at once; deleting it removes it")
    func addAndDeleteActivity() async throws {
        let f = await makeFixture(importing: {
            [Activity(source: .manual, sport: .running, start: $0, duration: 1800, distanceMeters: 5000, perceivedExertion: 5)]
        })
        let weekStart = f.viewModel.displayedWeekStart
        let activityDay = f.today
        // Prime every cache, with the data not there yet.
        _ = f.viewModel.sportStatsPages(asOf: f.today)
        _ = f.viewModel.dailyLoadSplit(for: weekStart, asOf: f.today)
        #expect(f.viewModel.dayMetrics(on: activityDay).metrics?.load == 0)

        await f.viewModel.refresh(asOf: f.today)

        #expect(runningPage(f)?.distanceMeters == 5000)
        #expect(f.viewModel.dailyLoadSplit(for: weekStart, asOf: f.today).actual.contains { $0.load > 0 })
        #expect((f.viewModel.dayMetrics(on: activityDay).metrics?.load ?? 0) > 0)
        #expect(f.viewModel.chartMetrics(for: weekStart).contains { $0.load > 0 })

        let stored = try #require(f.viewModel.activities(on: activityDay).first)
        await f.viewModel.deleteActivity(stored, asOf: f.today)

        #expect((runningPage(f)?.distanceMeters ?? 0) == 0)
        #expect(f.viewModel.dailyLoadSplit(for: weekStart, asOf: f.today).actual.isEmpty)
        #expect(f.viewModel.dayMetrics(on: activityDay).metrics?.load == 0)
    }

    @Test("a planned workout shows in the stats, the load chart and the metrics at once; deleting it removes it")
    func addAndDeletePlan() async throws {
        let f = await makeFixture()
        let weekStart = f.viewModel.displayedWeekStart
        _ = f.viewModel.sportStatsPages(asOf: f.today)
        _ = f.viewModel.dailyLoadSplit(for: weekStart, asOf: f.today)

        let workout = easyRun()
        let plan = PlannedActivity(workoutID: workout.id, date: f.tomorrow)
        try await f.model.add(workout, asOf: f.today)
        try await f.model.add(plan, asOf: f.today)

        #expect((runningPage(f)?.plannedTime ?? 0) == 1800)
        #expect(f.viewModel.dailyLoadSplit(for: weekStart, asOf: f.today).planned.contains { $0.load > 0 })
        #expect((f.viewModel.dayMetrics(on: f.tomorrow).metrics?.load ?? 0) > 0)

        try await f.model.deletePlan(id: plan.id, asOf: f.today)

        #expect((runningPage(f)?.plannedTime ?? 0) == 0)
        #expect(f.viewModel.dailyLoadSplit(for: weekStart, asOf: f.today).planned.isEmpty)
        #expect(f.viewModel.dayMetrics(on: f.tomorrow).metrics?.load == 0)
    }

    @Test("an activity changed in place (same count, e.g. after a resync) refreshes the stats and the load chart")
    func changedActivityInPlace() async throws {
        let f = await makeFixture()
        let weekStart = f.viewModel.displayedWeekStart
        let original = Activity(source: .manual, sport: .running, start: f.today, duration: 1800, distanceMeters: 5000, perceivedExertion: 5)
        try await f.store.upsert([original])
        await f.viewModel.load(asOf: f.today)
        #expect(runningPage(f)?.distanceMeters == 5000)
        let firstLoad = f.viewModel.dailyLoadSplit(for: weekStart, asOf: f.today).actual.first?.load

        var changed = original
        changed.distanceMeters = 8000
        changed.perceivedExertion = 8
        try await f.store.upsert([changed])
        await f.viewModel.load(asOf: f.today)

        #expect(runningPage(f)?.distanceMeters == 8000)
        let secondLoad = f.viewModel.dailyLoadSplit(for: weekStart, asOf: f.today).actual.first?.load
        #expect(try #require(secondLoad) > #require(firstLoad))
    }

    @Test("a missed planned workout (before today, never performed) counts nowhere")
    func missedPlanCountsNowhere() async throws {
        let f = await makeFixture()
        let weekStart = f.viewModel.displayedWeekStart
        // "Today" is mid-week; the plan is the day before and was never performed.
        let today = f.today.addingTimeInterval(3 * 86400)
        let missedDay = f.today.addingTimeInterval(2 * 86400)
        let workout = easyRun()
        try await f.model.add(workout, asOf: today)
        try await f.model.add(PlannedActivity(workoutID: workout.id, date: missedDay), asOf: today)

        let page = f.viewModel.sportStatsPages(asOf: today).first { $0.sport == .running }
        #expect((page?.plannedTime ?? 0) == 0)
        #expect((page?.plannedDistanceMeters ?? 0) == 0)
        #expect((page?.plannedLoad ?? 0) == 0)
        #expect((page?.time ?? 0) == 0)
        #expect(f.viewModel.dailyLoadSplit(for: weekStart, asOf: today).planned.isEmpty)
        #expect(f.viewModel.dailyLoadSplit(for: weekStart, asOf: today).actual.isEmpty)
        #expect(f.viewModel.dayMetrics(on: missedDay).metrics?.load == 0)
        #expect(f.viewModel.chartMetrics(for: weekStart).allSatisfy { $0.day >= today || $0.load == 0 })
    }
}

@MainActor
private final class ImportingRefresher: ActivityRefreshing {
    private let model: TrainingModel
    private let importer: any ActivityImporting

    init(model: TrainingModel, importer: any ActivityImporting) {
        self.model = model
        self.importer = importer
    }

    func refreshActivities(asOf today: Date) async throws {
        try await model.importActivities(from: importer, asOf: today)
    }

    func resyncActivities(asOf today: Date) async throws {
        try await model.resyncActivities(from: importer, asOf: today)
    }

    func requestAuthorization() async throws {}
}
