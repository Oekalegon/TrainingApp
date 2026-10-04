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
        #expect(await scheduler.keptPlanIDs == [[soon.id]])
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

    @Test("does nothing without permission to schedule workouts")
    func doesNothingWhenNotAuthorized() async throws {
        let (store, model) = try await makeModel()
        let steady = workout()
        try await store.upsert([steady])
        try await store.upsert([PlannedActivity(workoutID: steady.id, date: day(1))])
        let scheduler = FakeScheduler(isAuthorized: false)

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
}
