import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@MainActor
@Suite("WatchScheduleSync")
struct WatchScheduleSyncTests {
    private let scratch = ScratchDefaults()

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

    /// A sync whose banner dismissal lives in this test's own `UserDefaults` suite.
    private func makeSync(_ model: TrainingModel, _ scheduler: FakeScheduler) -> WatchScheduleSync {
        WatchScheduleSync(model: model, scheduler: scheduler, defaults: scratch.defaults)
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

        await makeSync(model, scheduler).sync(asOf: day(0))

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

        await makeSync(model, scheduler).sync(asOf: day(0))

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

        await makeSync(model, scheduler).sync(asOf: day(0))

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

        await makeSync(model, scheduler).sync(asOf: day(0))

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
        let sync = makeSync(model, scheduler)
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

        await makeSync(model, scheduler).sync(asOf: day(0))

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

        await makeSync(model, scheduler).sync(asOf: day(0))

        #expect(await scheduler.callLog == ["authorize", "unscheduleAll", "schedule", "schedule"])
    }

    // MARK: Permission banner (MVP2-117)

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
        let sync = makeSync(model, FakeScheduler(authorization: authorization))
        #expect(!sync.showsPermissionDeniedBanner)

        await sync.sync(asOf: day(0))

        #expect(sync.isPermissionDenied == showsBanner)
        #expect(sync.showsPermissionDeniedBanner == showsBanner)
    }

    @Test("shows the banner when denied even without a plan to send")
    func bannerWithoutUpcomingPlans() async throws {
        let (_, model) = try await makeModel()
        let scheduler = FakeScheduler(authorization: .denied)
        let sync = makeSync(model, scheduler)

        await sync.sync(asOf: day(0))

        #expect(await scheduler.callLog == ["authorizationStatus"])
        #expect(sync.showsPermissionDeniedBanner)
    }

    @Test("a dismissed banner stays away, also for a new sync object on the same defaults")
    func dismissalPersists() async throws {
        let model = try await makeModelWithUpcomingPlan()
        let scheduler = FakeScheduler(authorization: .denied)
        let sync = makeSync(model, scheduler)
        await sync.sync(asOf: day(0))

        sync.dismissPermissionDeniedBanner()
        #expect(!sync.showsPermissionDeniedBanner)
        await sync.sync(asOf: day(0))
        #expect(!sync.showsPermissionDeniedBanner)

        let relaunched = makeSync(model, scheduler)
        await relaunched.sync(asOf: day(0))
        #expect(relaunched.isPermissionDenied)
        #expect(!relaunched.showsPermissionDeniedBanner)
    }

    @Test("allowing permission hides the banner, and declining again later brings it back")
    func grantingResetsDismissal() async throws {
        let model = try await makeModelWithUpcomingPlan()
        let scheduler = FakeScheduler(authorization: .denied)
        let sync = makeSync(model, scheduler)
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

    // MARK: Athlete tab (MVP2-117)

    @Test("refreshing reads the permission without asking or syncing")
    func refreshAuthorizationDoesNotPrompt() async throws {
        let model = try await makeModelWithUpcomingPlan()
        let scheduler = FakeScheduler(authorization: .denied)
        let sync = makeSync(model, scheduler)
        #expect(sync.authorization == nil)

        await sync.refreshAuthorization()

        #expect(sync.authorization == .denied)
        #expect(sync.showsPermissionDeniedBanner)
        #expect(await scheduler.callLog == ["authorizationStatus"])
    }

    @Test("allowing from the Athlete tab asks, then syncs once granted")
    func requestPermissionSyncsWhenGranted() async throws {
        let model = try await makeModelWithUpcomingPlan()
        let scheduler = FakeScheduler(authorization: .authorized)
        let sync = makeSync(model, scheduler)

        await sync.requestPermission(asOf: day(0))

        #expect(sync.authorization == .authorized)
        #expect(await scheduler.callLog == ["authorize", "authorize", "unscheduleAll", "schedule"])
    }

    @Test("allowing from the Athlete tab doesn't sync when permission stays declined")
    func requestPermissionDeclined() async throws {
        let model = try await makeModelWithUpcomingPlan()
        let scheduler = FakeScheduler(authorization: .denied)
        let sync = makeSync(model, scheduler)

        await sync.requestPermission(asOf: day(0))

        #expect(sync.authorization == .denied)
        #expect(await scheduler.callLog == ["authorize"])
    }

    // MARK: Send to Apple Watch switch (MVP2-118)

    @Test("sending is on by default")
    func enabledByDefault() async throws {
        let (_, model) = try await makeModel()
        let sync = makeSync(model, FakeScheduler())

        #expect(sync.isEnabled)
        #expect(sync.editingScheduler != nil)
    }

    @Test("turning sending off removes every entry and keeps the plans off the Watch")
    func turningOffRemovesEntries() async throws {
        let model = try await makeModelWithUpcomingPlan()
        let scheduler = FakeScheduler()
        let sync = makeSync(model, scheduler)

        await sync.setEnabled(false, asOf: day(0)).value
        await sync.sync(asOf: day(0))

        #expect(!sync.isEnabled)
        #expect(sync.editingScheduler == nil)
        #expect(await scheduler.callLog == [
            "authorizationStatus", "unscheduleAll",
            "authorizationStatus", "unscheduleAll",
        ])
        #expect(await scheduler.keptPlanIDs == [[], []])
        #expect(await scheduler.scheduledPlans.isEmpty)
    }

    @Test("turned off, a sync never asks for permission")
    func turnedOffDoesNotPrompt() async throws {
        let model = try await makeModelWithUpcomingPlan()
        let scheduler = FakeScheduler(authorization: .notDetermined)
        let sync = makeSync(model, scheduler)

        await sync.setEnabled(false, asOf: day(0)).value

        #expect(await scheduler.callLog == ["authorizationStatus"])
        #expect(sync.authorization == .notDetermined)
    }

    @Test("the switch is remembered across launches")
    func enabledPersists() async throws {
        let (_, model) = try await makeModel()
        let scheduler = FakeScheduler()
        await makeSync(model, scheduler).setEnabled(false, asOf: day(0)).value

        #expect(!makeSync(model, scheduler).isEnabled)
    }

    @Test("turning sending back on asks for permission if needed, then schedules the plans")
    func turningOnSyncs() async throws {
        let model = try await makeModelWithUpcomingPlan()
        let scheduler = FakeScheduler()
        let sync = makeSync(model, scheduler)
        await sync.setEnabled(false, asOf: day(0)).value

        await sync.setEnabled(true, asOf: day(0)).value

        #expect(sync.isEnabled)
        #expect(await scheduler.callLog.suffix(4) == ["authorize", "authorize", "unscheduleAll", "schedule"])
        #expect(await scheduler.scheduledPlans.count == 1)
    }

    @Test("setting the switch to what it already is does nothing")
    func unchangedSwitchIsNoOp() async throws {
        let (_, model) = try await makeModel()
        let scheduler = FakeScheduler()

        await makeSync(model, scheduler).setEnabled(true, asOf: day(0)).value

        #expect(await scheduler.callLog.isEmpty)
    }

    @Test("turning sending off during a sync stops it scheduling, then clears the Watch")
    func turningOffDuringSync() async throws {
        let model = try await makeModelWithUpcomingPlan()
        let scheduler = FakeScheduler()
        let sync = makeSync(model, scheduler)
        let now = day(0)
        await scheduler.setDuringFirstUnscheduleAll {
            await sync.setEnabled(false, asOf: now).value
        }

        await sync.sync(asOf: now)

        #expect(await scheduler.scheduledPlans.isEmpty)
        #expect(await scheduler.keptPlanIDs.last == Set<UUID>())
    }

    @Test("turning sending back on during the turn-off sync puts the plans back")
    func turningOnDuringTurnOff() async throws {
        let model = try await makeModelWithUpcomingPlan()
        let scheduler = FakeScheduler()
        let sync = makeSync(model, scheduler)
        let now = day(0)
        await scheduler.setDuringFirstUnscheduleAll {
            await sync.setEnabled(true, asOf: now).value
        }

        await sync.setEnabled(false, asOf: now).value

        #expect(sync.isEnabled)
        #expect(await scheduler.scheduledPlans.count == 1)
    }

    @Test("no permission banner while sending is turned off")
    func noBannerWhenTurnedOff() async throws {
        let model = try await makeModelWithUpcomingPlan()
        let sync = makeSync(model, FakeScheduler(authorization: .denied))
        await sync.sync(asOf: day(0))
        #expect(sync.showsPermissionDeniedBanner)

        await sync.setEnabled(false, asOf: day(0)).value

        #expect(sync.isPermissionDenied)
        #expect(!sync.showsPermissionDeniedBanner)
    }

    // MARK: Card status (MVP2-119)

    @Test("remembers the plans it sent, and why workouts can't go on the Watch")
    func recordsSentPlansAndUnsupportedWorkouts() async throws {
        let (store, model) = try await makeModel()
        let good = workout()
        let bad = workout()
        try await store.upsert([good, bad])
        let goodPlan = PlannedActivity(workoutID: good.id, date: day(1))
        let badPlan = PlannedActivity(workoutID: bad.id, date: day(2))
        let later = PlannedActivity(workoutID: good.id, date: day(20))
        try await store.upsert([goodPlan, badPlan, later])
        let sync = makeSync(model, FakeScheduler(invalidWorkoutIDs: [bad.id]))

        await sync.sync(asOf: day(0))

        #expect(sync.sentPlanIDs == [goodPlan.id])
        #expect(sync.unsupportedWorkouts == [bad.id: FakeScheduler.unsupportedReason])
    }

    @Test("a plan that fails to schedule isn't counted as sent")
    func failedScheduleIsNotSent() async throws {
        let model = try await makeModelWithUpcomingPlan()
        let sync = makeSync(model, FakeScheduler(scheduleShouldFail: true))

        await sync.sync(asOf: day(0))

        #expect(sync.sentPlanIDs.isEmpty)
    }

    @Test("without permission nothing counts as sent, but unsupported workouts are still found")
    func notAuthorizedSendsNothing() async throws {
        let (store, model) = try await makeModel()
        let bad = workout()
        try await store.upsert([bad])
        try await store.upsert([PlannedActivity(workoutID: bad.id, date: day(1))])
        let sync = makeSync(model, FakeScheduler(authorization: .denied, invalidWorkoutIDs: [bad.id]))

        await sync.sync(asOf: day(0))

        #expect(sync.sentPlanIDs.isEmpty)
        #expect(sync.unsupportedWorkouts.keys.contains(bad.id))
    }

    @Test("turning sending off forgets the plans it sent")
    func turningOffClearsSentPlans() async throws {
        let model = try await makeModelWithUpcomingPlan()
        let sync = makeSync(model, FakeScheduler())
        await sync.sync(asOf: day(0))
        #expect(sync.sentPlanIDs.count == 1)

        await sync.setEnabled(false, asOf: day(0)).value

        #expect(sync.sentPlanIDs.isEmpty)
    }
}
