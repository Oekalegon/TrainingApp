import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

/// The Watch sync runs again after anything that can link or unlink a plan (MVP2-114).
///
/// `requestSync()` syncs as of the real `.now`, so the plan here sits at noon today (UTC athlete):
/// inside the window, where linking decides whether it's scheduled or only kept.
@MainActor
@Suite("WeekViewModel Watch sync (MVP2-114)")
struct WeekViewModelWatchSyncTests {
    private struct StubImporter: ActivityImporting {
        let activities: [Activity]
        func importActivities(since anchor: ImportAnchor?) async throws -> ImportResult {
            ImportResult(upserted: activities, deletedSources: [], anchor: nil)
        }
    }

    private var noonToday: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(byAdding: .hour, value: 12, to: calendar.startOfDay(for: .now))!
    }

    /// A plan at noon today and an imported activity matched to it, with a Watch sync on `scheduler`.
    private func makeViewModel(
        scheduler: FakeScheduler, refresher: FakeRefresher = FakeRefresher()
    ) async throws -> (WeekViewModel, PlannedActivity, Activity) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        let model = TrainingModel(stores: stores, athlete: AthleteProfile.fixture(timeZoneIdentifier: "UTC"))
        let today = noonToday
        let workout = StructuredWorkout(
            name: "Steady", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800))])]
        )
        try await model.add(workout, asOf: today)
        let plan = PlannedActivity(workoutID: workout.id, date: today)
        try await model.add(plan, asOf: today)
        try await model.load(in: today.addingTimeInterval(-3 * 86400)...today.addingTimeInterval(3 * 86400), asOf: today)
        let activity = Activity(source: .healthKit(UUID()), sport: .running, start: today, duration: 1800)
        try await model.importActivities(from: StubImporter(activities: [activity]), asOf: today)
        let viewModel = WeekViewModel(
            model: model, refresher: refresher,
            watchSync: WatchScheduleSync(model: model, scheduler: scheduler), today: today
        )
        return (viewModel, plan, model.activities[0])
    }

    @Test("unlinking puts the plan back on the Watch")
    func unlinkSchedulesPlan() async throws {
        let scheduler = FakeScheduler()
        let (viewModel, plan, activity) = try await makeViewModel(scheduler: scheduler)

        #expect(await viewModel.unlinkActivity(activity, asOf: noonToday))
        await viewModel.pendingWatchSync?.value

        #expect(await scheduler.scheduledPlans.map(\.id) == [plan.id])
    }

    @Test("linking keeps the plan's entry as done instead of scheduling it again")
    func linkKeepsPlan() async throws {
        let scheduler = FakeScheduler()
        let (viewModel, plan, activity) = try await makeViewModel(scheduler: scheduler)

        #expect(await viewModel.linkActivity(activity, toPlan: plan.id, asOf: noonToday))
        await viewModel.pendingWatchSync?.value

        #expect(await scheduler.scheduledPlans.isEmpty)
        #expect(await scheduler.keptPlanIDs.last == [plan.id])
    }

    @Test("a refused link doesn't sync")
    func failedLinkDoesNotSync() async throws {
        let scheduler = FakeScheduler()
        let (viewModel, plan, activity) = try await makeViewModel(scheduler: scheduler)
        // Linking to a plan on another day is refused.
        let tomorrow = PlannedActivity(workoutID: plan.workoutID, date: noonToday.addingTimeInterval(86400))
        try await viewModel.model.add(tomorrow, asOf: noonToday)

        #expect(await viewModel.linkActivity(activity, toPlan: tomorrow.id, asOf: noonToday) == false)

        #expect(viewModel.pendingWatchSync == nil)
        #expect(await scheduler.callLog.isEmpty)
    }

    @Test("a HealthKit refresh syncs afterwards")
    func refreshSyncs() async throws {
        let scheduler = FakeScheduler()
        let refresher = FakeRefresher()
        let (viewModel, plan, _) = try await makeViewModel(scheduler: scheduler, refresher: refresher)

        await viewModel.refresh(asOf: noonToday)
        await viewModel.pendingWatchSync?.value

        #expect(refresher.callCount == 1)
        #expect(await scheduler.keptPlanIDs == [[plan.id]])
    }

    @Test("deleting the activity a plan was linked to puts the plan back on the Watch")
    func deleteActivitySchedulesPlan() async throws {
        let scheduler = FakeScheduler()
        let (viewModel, plan, activity) = try await makeViewModel(scheduler: scheduler)

        await viewModel.deleteActivity(activity, asOf: noonToday)
        await viewModel.pendingWatchSync?.value

        #expect(await scheduler.scheduledPlans.map(\.id) == [plan.id])
    }
}
