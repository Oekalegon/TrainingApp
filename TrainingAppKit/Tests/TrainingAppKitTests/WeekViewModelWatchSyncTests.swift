import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

/// The Watch sync runs again after anything that can link or unlink a plan (MVP2-116), as of the
/// action's injected day.
///
/// The plan sits on day 2, which is also "today", so it's inside the 7-day window: linking decides
/// whether it's scheduled or only kept as done.
@MainActor
@Suite("WeekViewModel Watch sync (MVP2-116)")
struct WeekViewModelWatchSyncTests {
    private struct StubImporter: ActivityImporting {
        let activities: [Activity]
        func importActivities(since anchor: ImportAnchor?) async throws -> ImportResult {
            ImportResult(upserted: activities, deletedSources: [], anchor: nil)
        }
    }

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private var today: Date { day(2) }

    /// A 30-minute run planned today, and the activities in `extra` imported along with a matching
    /// 30-minute run (so the plan is auto-linked to it, as in the app).
    private func makeViewModel(
        scheduler: FakeScheduler?,
        refresher: FakeRefresher = FakeRefresher(),
        extra: [Activity] = []
    ) async throws -> (WeekViewModel, PlannedActivity, Activity) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        let model = TrainingModel(stores: stores, athlete: AthleteProfile.fixture(timeZoneIdentifier: "UTC"))
        let workout = StructuredWorkout(
            name: "Steady", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800))])]
        )
        try await model.add(workout, asOf: today)
        let plan = PlannedActivity(workoutID: workout.id, date: today)
        try await model.add(plan, asOf: today)
        try await model.load(in: day(0)...day(6), asOf: today)
        let run = Activity(source: .healthKit(UUID()), sport: .running, start: today, duration: 1800)
        try await model.importActivities(from: StubImporter(activities: [run] + extra), asOf: today)
        let viewModel = WeekViewModel(
            model: model, refresher: refresher,
            watchSync: scheduler.map { WatchScheduleSync(model: model, scheduler: $0) }, today: today
        )
        let linked = try #require(model.activities.first { $0.linkedPlanID == plan.id })
        return (viewModel, plan, linked)
    }

    /// The sync ran and kept `plan`'s entry as done, without scheduling it again.
    private func expectKeptAsDone(_ plan: PlannedActivity, by scheduler: FakeScheduler) async {
        #expect(await scheduler.callLog == ["authorizationStatus", "unscheduleAll"])
        #expect(await scheduler.keptPlanIDs == [[plan.id]])
    }

    // MARK: Linking

    @Test("unlinking puts the plan back on the Watch")
    func unlinkSchedulesPlan() async throws {
        let scheduler = FakeScheduler()
        let (viewModel, plan, activity) = try await makeViewModel(scheduler: scheduler)

        #expect(await viewModel.unlinkActivity(activity, asOf: today))
        await viewModel.pendingWatchSync?.value

        #expect(await scheduler.scheduledPlans.map(\.id) == [plan.id])
    }

    @Test("linking keeps the plan's entry as done instead of scheduling it again")
    func linkKeepsPlan() async throws {
        let scheduler = FakeScheduler()
        let (viewModel, plan, activity) = try await makeViewModel(scheduler: scheduler)

        #expect(await viewModel.linkActivity(activity, toPlan: plan.id, asOf: today))
        await viewModel.pendingWatchSync?.value

        await expectKeptAsDone(plan, by: scheduler)
    }

    @Test("a refused link doesn't sync")
    func failedLinkDoesNotSync() async throws {
        let scheduler = FakeScheduler()
        let (viewModel, plan, activity) = try await makeViewModel(scheduler: scheduler)
        // Linking to a plan on another day is refused.
        let tomorrow = PlannedActivity(workoutID: plan.workoutID, date: day(3))
        try await viewModel.model.add(tomorrow, asOf: today)

        #expect(await viewModel.linkActivity(activity, toPlan: tomorrow.id, asOf: today) == false)

        #expect(viewModel.pendingWatchSync == nil)
        #expect(await scheduler.callLog.isEmpty)
    }

    // MARK: Imports

    @Test("a HealthKit refresh syncs afterwards")
    func refreshSyncs() async throws {
        let scheduler = FakeScheduler()
        let refresher = FakeRefresher()
        let (viewModel, plan, _) = try await makeViewModel(scheduler: scheduler, refresher: refresher)

        await viewModel.refresh(asOf: today)
        await viewModel.pendingWatchSync?.value

        #expect(refresher.callCount == 1)
        await expectKeptAsDone(plan, by: scheduler)
    }

    @Test("Connect Health syncs after a successful import")
    func connectHealthSyncs() async throws {
        let scheduler = FakeScheduler()
        let (viewModel, plan, _) = try await makeViewModel(scheduler: scheduler)

        await viewModel.connectHealthData(asOf: today)
        await viewModel.pendingWatchSync?.value

        await expectKeptAsDone(plan, by: scheduler)
    }

    @Test("Connect Health doesn't sync when authorization or the import fails")
    func failedConnectHealthDoesNotSync() async throws {
        let scheduler = FakeScheduler()
        let (viewModel, _, _) = try await makeViewModel(
            scheduler: scheduler, refresher: FakeRefresher(shouldThrow: true)
        )

        await viewModel.connectHealthData(asOf: today)

        #expect(viewModel.pendingWatchSync == nil)
        #expect(await scheduler.callLog.isEmpty)
    }

    @Test("a full resync syncs afterwards, even when the import fails")
    func resyncSyncsEvenOnFailure() async throws {
        let scheduler = FakeScheduler()
        let refresher = FakeRefresher(shouldThrow: true)
        let (viewModel, plan, _) = try await makeViewModel(scheduler: scheduler, refresher: refresher)

        await viewModel.resyncActivities(asOf: today)
        await viewModel.pendingWatchSync?.value

        #expect(refresher.resyncCallCount == 1)
        await expectKeptAsDone(plan, by: scheduler)
    }

    @Test("deduplicating syncs afterwards")
    func deduplicateSyncs() async throws {
        let scheduler = FakeScheduler()
        let (viewModel, plan, _) = try await makeViewModel(scheduler: scheduler)

        await viewModel.deduplicateActivities(asOf: today)
        await viewModel.pendingWatchSync?.value

        await expectKeptAsDone(plan, by: scheduler)
    }

    // MARK: Deleting, joining and unjoining

    @Test("deleting the activity a plan was linked to puts the plan back on the Watch")
    func deleteActivitySchedulesPlan() async throws {
        let scheduler = FakeScheduler()
        let (viewModel, plan, activity) = try await makeViewModel(scheduler: scheduler)

        await viewModel.deleteActivity(activity, asOf: today)
        await viewModel.pendingWatchSync?.value

        #expect(await scheduler.scheduledPlans.map(\.id) == [plan.id])
    }

    @Test("joining and unjoining sync afterwards, and the plan stays done through both")
    func joinAndUnjoinSync() async throws {
        let rest = Activity(
            source: .healthKit(UUID()), sport: .running, start: today.addingTimeInterval(1900), duration: 600
        )
        let joinScheduler = FakeScheduler()
        let (joining, plan, activity) = try await makeViewModel(scheduler: joinScheduler, extra: [rest])
        let otherPiece = try #require(joining.model.activities.first { $0.id != activity.id })

        #expect(await joining.joinActivities(activity, with: otherPiece, asOf: today))
        await joining.pendingWatchSync?.value
        await expectKeptAsDone(plan, by: joinScheduler)

        let joined = try #require(joining.model.activities.first { $0.linkedPlanID == plan.id })
        #expect(await joining.unjoinActivity(joined, asOf: today))
        await joining.pendingWatchSync?.value
        #expect(await joinScheduler.keptPlanIDs.count == 2)
        #expect(await joinScheduler.keptPlanIDs.last == [plan.id])
        #expect(await joinScheduler.scheduledPlans.isEmpty)
    }

    @Test("a refused join doesn't sync")
    func failedJoinDoesNotSync() async throws {
        let ride = Activity(
            source: .healthKit(UUID()), sport: .cycling, start: today.addingTimeInterval(1900), duration: 600
        )
        let scheduler = FakeScheduler()
        let (viewModel, _, activity) = try await makeViewModel(scheduler: scheduler, extra: [ride])
        let otherPiece = try #require(viewModel.model.activities.first { $0.id != activity.id })

        #expect(await viewModel.joinActivities(activity, with: otherPiece, asOf: today) == false)

        #expect(viewModel.pendingWatchSync == nil)
        #expect(await scheduler.callLog.isEmpty)
    }

    // MARK: Without a Watch sync

    @Test("without a Watch sync, the same actions work and start nothing")
    func noWatchSync() async throws {
        let (viewModel, plan, activity) = try await makeViewModel(scheduler: nil)

        #expect(await viewModel.linkActivity(activity, toPlan: plan.id, asOf: today))
        await viewModel.refresh(asOf: today)
        await viewModel.deleteActivity(activity, asOf: today)

        #expect(viewModel.pendingWatchSync == nil)
        #expect(viewModel.model.activities.isEmpty)
    }

    // MARK: Permission banner (MVP2-117)

    @Test("shows the Watch permission banner after a sync finds permission denied, until dismissed")
    func permissionBanner() async throws {
        let suiteName = "WeekViewModelWatchSyncTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let (viewModel, _, _) = try await makeViewModel(scheduler: nil)
        #expect(!viewModel.showsWatchPermissionBanner)

        let sync = WatchScheduleSync(
            model: viewModel.model, scheduler: FakeScheduler(authorization: .denied), defaults: defaults
        )
        let withSync = WeekViewModel(model: viewModel.model, refresher: FakeRefresher(), watchSync: sync, today: today)
        #expect(!withSync.showsWatchPermissionBanner)
        await sync.sync(asOf: today)
        #expect(withSync.showsWatchPermissionBanner)

        withSync.dismissWatchPermissionBanner()
        #expect(!withSync.showsWatchPermissionBanner)
    }
}
