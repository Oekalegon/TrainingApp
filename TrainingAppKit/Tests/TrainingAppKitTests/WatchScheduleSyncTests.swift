import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@MainActor
@Suite("WatchScheduleSync")
struct WatchScheduleSyncTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func makeModel() async throws -> (InMemoryStore, TrainingModel) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        try await store.save(athlete)
        return (store, TrainingModel(stores: stores, athlete: athlete))
    }

    private func workout() -> StructuredWorkout {
        StructuredWorkout(
            name: "Steady", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800), target: .heartRateZone(2))])]
        )
    }

    @Test("removes stale entries, then schedules the next 7 days of plans")
    func schedulesWindow() async throws {
        let (store, model) = try await makeModel()
        let steady = workout()
        try await store.upsert([steady])
        let past = PlannedActivity(workoutID: steady.id, date: day(-2))
        let soon = PlannedActivity(workoutID: steady.id, date: day(2))
        let later = PlannedActivity(workoutID: steady.id, date: day(20))
        try await store.upsert([past, soon, later])
        let scheduler = FakeScheduler()

        await WatchScheduleSync(model: model, scheduler: scheduler).sync(asOf: day(0))

        #expect(await scheduler.callLog == ["authorize", "unscheduleAll", "schedule"])
        // The past plan keeps its entry: it may have been done and not linked yet.
        #expect(await scheduler.keptPlanIDs == [[past.id, soon.id]])
        #expect(await scheduler.scheduledPlans.map(\.id) == [soon.id])
    }

    @Test("reads plans from the store, not just the range the week view loaded")
    func readsAllPlans() async throws {
        let (store, model) = try await makeModel()
        try await model.load(in: day(30)...day(40), asOf: day(0))
        let steady = workout()
        try await store.upsert([steady])
        let soon = PlannedActivity(workoutID: steady.id, date: day(1))
        try await store.upsert([soon])
        let scheduler = FakeScheduler()

        await WatchScheduleSync(model: model, scheduler: scheduler).sync(asOf: day(0))

        #expect(await scheduler.scheduledPlans.map(\.id) == [soon.id])
    }

    @Test("skips plans whose workout is missing or can't go on the Watch")
    func skipsUnschedulablePlans() async throws {
        let (store, model) = try await makeModel()
        let good = workout()
        let bad = workout()
        try await store.upsert([good, bad])
        let goodPlan = PlannedActivity(workoutID: good.id, date: day(1))
        let badPlan = PlannedActivity(workoutID: bad.id, date: day(2))
        let orphan = PlannedActivity(workoutID: UUID(), date: day(3))
        try await store.upsert([goodPlan, badPlan, orphan])
        let scheduler = FakeScheduler(invalidWorkoutIDs: [bad.id])

        await WatchScheduleSync(model: model, scheduler: scheduler).sync(asOf: day(0))

        #expect(await scheduler.scheduledPlans.map(\.id) == [goodPlan.id])
        #expect(await scheduler.keptPlanIDs == [[goodPlan.id]])
    }

    @Test("doesn't ask for permission while there's nothing to send, but still clears old entries")
    func noPromptWithoutUpcomingPlans() async throws {
        let (store, model) = try await makeModel()
        let steady = workout()
        try await store.upsert([steady])
        try await store.upsert([PlannedActivity(workoutID: steady.id, date: day(20))])
        let scheduler = FakeScheduler()

        await WatchScheduleSync(model: model, scheduler: scheduler).sync(asOf: day(0))

        #expect(await scheduler.callLog == ["authorizationStatus", "unscheduleAll"])
        #expect(await scheduler.keptPlanIDs == [[]])
    }

    @Test("a sync requested during a run makes that run go round again instead of being dropped")
    func requestDuringRunReruns() async throws {
        let (store, model) = try await makeModel()
        let steady = workout()
        try await store.upsert([steady])
        let soon = PlannedActivity(workoutID: steady.id, date: day(1))
        try await store.upsert([soon])
        let scheduler = FakeScheduler()
        let sync = WatchScheduleSync(model: model, scheduler: scheduler)
        let now = day(0)
        await scheduler.setDuringFirstUnscheduleAll {
            await sync.sync(asOf: now)
        }

        await sync.sync(asOf: now)

        #expect(await scheduler.callLog == [
            "authorize", "unscheduleAll", "schedule",
            "authorize", "unscheduleAll", "schedule",
        ])
    }

    @Test("does nothing without permission to schedule workouts")
    func doesNothingWhenNotAuthorized() async throws {
        let (store, model) = try await makeModel()
        let steady = workout()
        try await store.upsert([steady])
        try await store.upsert([PlannedActivity(workoutID: steady.id, date: day(1))])
        let scheduler = FakeScheduler(authorization: .denied)

        await WatchScheduleSync(model: model, scheduler: scheduler).sync(asOf: day(0))

        #expect(await scheduler.callLog == ["authorize"])
    }

    @Test("a plan that fails to schedule doesn't stop the run")
    func scheduleFailureIsSkipped() async throws {
        let (store, model) = try await makeModel()
        let steady = workout()
        try await store.upsert([steady])
        try await store.upsert([
            PlannedActivity(workoutID: steady.id, date: day(1)),
            PlannedActivity(workoutID: steady.id, date: day(2)),
        ])
        let scheduler = FakeScheduler(scheduleShouldFail: true)

        await WatchScheduleSync(model: model, scheduler: scheduler).sync(asOf: day(0))

        #expect(await scheduler.callLog == ["authorize", "unscheduleAll", "schedule", "schedule"])
    }

    // MARK: Permission banner (MVP2-117)

    /// A fresh `UserDefaults` suite, so the banner's dismissal doesn't leak between tests.
    private func makeDefaults() -> UserDefaults {
        let name = "WatchScheduleSyncTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// A model with one plan tomorrow, so a sync asks for permission.
    private func makeModelWithUpcomingPlan() async throws -> TrainingModel {
        let (store, model) = try await makeModel()
        let steady = workout()
        try await store.upsert([steady])
        try await store.upsert([PlannedActivity(workoutID: steady.id, date: day(1))])
        return model
    }

    @Test("shows the banner once a sync finds permission denied", arguments: [
        (WatchSchedulingAuthorization.denied, true),
        (WatchSchedulingAuthorization.authorized, false),
        (WatchSchedulingAuthorization.notDetermined, false),
        (WatchSchedulingAuthorization.unavailable, false),
    ])
    func bannerFollowsAuthorization(authorization: WatchSchedulingAuthorization, showsBanner: Bool) async throws {
        let model = try await makeModelWithUpcomingPlan()
        let sync = WatchScheduleSync(
            model: model, scheduler: FakeScheduler(authorization: authorization), defaults: makeDefaults()
        )
        #expect(!sync.showsPermissionDeniedBanner)

        await sync.sync(asOf: day(0))

        #expect(sync.isPermissionDenied == showsBanner)
        #expect(sync.showsPermissionDeniedBanner == showsBanner)
    }

    @Test("shows the banner when denied even without a plan to send")
    func bannerWithoutUpcomingPlans() async throws {
        let (_, model) = try await makeModel()
        let scheduler = FakeScheduler(authorization: .denied)
        let sync = WatchScheduleSync(model: model, scheduler: scheduler, defaults: makeDefaults())

        await sync.sync(asOf: day(0))

        #expect(await scheduler.callLog == ["authorizationStatus"])
        #expect(sync.showsPermissionDeniedBanner)
    }

    @Test("a dismissed banner stays away, also for a new sync object on the same defaults")
    func dismissalPersists() async throws {
        let model = try await makeModelWithUpcomingPlan()
        let defaults = makeDefaults()
        let scheduler = FakeScheduler(authorization: .denied)
        let sync = WatchScheduleSync(model: model, scheduler: scheduler, defaults: defaults)
        await sync.sync(asOf: day(0))

        sync.dismissPermissionDeniedBanner()
        #expect(!sync.showsPermissionDeniedBanner)
        await sync.sync(asOf: day(0))
        #expect(!sync.showsPermissionDeniedBanner)

        let relaunched = WatchScheduleSync(model: model, scheduler: scheduler, defaults: defaults)
        await relaunched.sync(asOf: day(0))
        #expect(relaunched.isPermissionDenied)
        #expect(!relaunched.showsPermissionDeniedBanner)
    }

    @Test("allowing permission hides the banner, and declining again later brings it back")
    func grantingResetsDismissal() async throws {
        let model = try await makeModelWithUpcomingPlan()
        let scheduler = FakeScheduler(authorization: .denied)
        let sync = WatchScheduleSync(model: model, scheduler: scheduler, defaults: makeDefaults())
        await sync.sync(asOf: day(0))
        sync.dismissPermissionDeniedBanner()

        await scheduler.setAuthorization(.authorized)
        await sync.sync(asOf: day(0))
        #expect(!sync.isPermissionDenied)
        #expect(!sync.showsPermissionDeniedBanner)

        await scheduler.setAuthorization(.denied)
        await sync.sync(asOf: day(0))
        #expect(sync.showsPermissionDeniedBanner)
    }
}
