import Foundation
import Testing
import TrainingCore
import TrainingWatchKit
@testable import TrainingAppKit

@MainActor
private final class FakeSender: WatchSyncSending {
    struct Failure: Error {}
    var plans: [WatchPlan] = []
    var failing = false
    var lastSendError: String?

    func send(zones: WatchZones) throws {}

    func send(plan: WatchPlan) throws {
        if failing { throw Failure() }
        plans.append(plan)
    }
}

/// A workout library whose reads fail.
private struct FailingWorkoutStore: WorkoutLibraryStore {
    struct Failure: Error {}

    func workouts() async throws -> [StructuredWorkout] { throw Failure() }
    func workout(id: UUID) async throws -> StructuredWorkout? { nil }
    func upsert(_ workouts: [StructuredWorkout]) async throws {}
    func deleteWorkout(id: UUID) async throws {}
}

@MainActor
@Suite("WatchPlanSync (WATCH-103)")
struct WatchPlanSyncTests {
    private let scratch = ScratchDefaults()

    /// A day offset from a fixed UTC midnight, plus `hours`.
    private func day(_ offset: Int, hours: Double = 8) -> Date {
        Date(timeIntervalSince1970: 1_700_006_400 + Double(offset) * 86400 + hours * 3600)
    }

    private func makeModel(failingWorkouts: Bool = false) async throws -> (InMemoryStore, TrainingModel) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: failingWorkouts ? FailingWorkoutStore() : store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        try await store.save(athlete)
        return (store, TrainingModel(stores: stores, athlete: athlete))
    }

    private func workout(_ name: String = "Steady", sport: Sport = .running) -> StructuredWorkout {
        StructuredWorkout(
            name: name, sport: sport,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800), target: .heartRateZone(2))])])
    }

    @Test("sends the planned runs of the next 7 days, earliest first, with their workouts")
    func sendsWindow() async throws {
        let (store, model) = try await makeModel()
        let easy = workout("Easy"), tempo = workout("Tempo")
        try await store.upsert([easy, tempo])
        let tomorrow = PlannedActivity(workoutID: tempo.id, date: day(1))
        let today = PlannedActivity(workoutID: easy.id, date: day(0))
        let lastDay = PlannedActivity(workoutID: easy.id, date: day(6))
        try await store.upsert([tomorrow, today, lastDay])
        let sender = FakeSender()

        await WatchPlanSync(model: model, sender: sender).sync(asOf: day(0, hours: 12))

        let sent = try #require(sender.plans.first)
        #expect(sender.plans.count == 1)
        #expect(sent.workouts.map(\.id) == [today.id, tomorrow.id, lastDay.id])
        #expect(sent.workouts.map(\.workout.name) == ["Easy", "Tempo", "Easy"])
    }

    @Test("leaves out the past, beyond the window, completed plans, other sports and missing workouts")
    func leavesOut() async throws {
        let (store, model) = try await makeModel()
        let run = workout(), ride = workout("Ride", sport: .cycling)
        try await store.upsert([run, ride])
        let kept = PlannedActivity(workoutID: run.id, date: day(2))
        let past = PlannedActivity(workoutID: run.id, date: day(-1))
        let tooFar = PlannedActivity(workoutID: run.id, date: day(7))
        let completed = PlannedActivity(workoutID: run.id, date: day(1), completedActivityID: UUID())
        let cycling = PlannedActivity(workoutID: ride.id, date: day(1))
        let orphan = PlannedActivity(workoutID: UUID(), date: day(3))
        try await store.upsert([kept, past, tooFar, completed, cycling, orphan])
        let sender = FakeSender()

        await WatchPlanSync(model: model, sender: sender).sync(asOf: day(0, hours: 12))

        #expect(sender.plans.first?.workouts.map(\.id) == [kept.id])
    }

    @Test("today starts at midnight in the athlete's time zone")
    func dayBoundary() async throws {
        let (store, model) = try await makeModel()
        let run = workout()
        try await store.upsert([run])
        let earlyToday = PlannedActivity(workoutID: run.id, date: day(0, hours: 0.5))
        let lateYesterday = PlannedActivity(workoutID: run.id, date: day(0, hours: -0.5))
        try await store.upsert([earlyToday, lateYesterday])
        let sender = FakeSender()

        await WatchPlanSync(model: model, sender: sender).sync(asOf: day(0, hours: 22))

        #expect(sender.plans.first?.workouts.map(\.id) == [earlyToday.id])
    }

    @Test("an empty plan is sent too, so the watch clears what it had")
    func emptyPlanIsSent() async throws {
        let (_, model) = try await makeModel()
        let sender = FakeSender()
        await WatchPlanSync(model: model, sender: sender).sync(asOf: day(0))
        #expect(sender.plans == [WatchPlan(workouts: [])])
    }

    @Test("an unchanged plan isn't sent again, and a changed one is")
    func sendsOnlyChanges() async throws {
        let (store, model) = try await makeModel()
        let run = workout()
        try await store.upsert([run])
        try await store.upsert([PlannedActivity(workoutID: run.id, date: day(1))])
        let sender = FakeSender()
        let sync = WatchPlanSync(model: model, sender: sender)

        await sync.sync(asOf: day(0))
        await sync.sync(asOf: day(0))
        #expect(sender.plans.count == 1)

        try await store.upsert([PlannedActivity(workoutID: run.id, date: day(2))])
        await sync.sync(asOf: day(0))
        #expect(sender.plans.count == 2)
        #expect(sender.plans.last?.workouts.count == 2)
    }

    @Test("a plan completed since the last send is sent again without it")
    func completedPlanDropsOut() async throws {
        let (store, model) = try await makeModel()
        let run = workout()
        try await store.upsert([run])
        let plan = PlannedActivity(workoutID: run.id, date: day(0))
        try await store.upsert([plan])
        let sender = FakeSender()
        let sync = WatchPlanSync(model: model, sender: sender)
        await sync.sync(asOf: day(0))

        var done = plan
        done.completedActivityID = UUID()
        try await store.upsert([done])
        await sync.sync(asOf: day(0))

        #expect(sender.plans.last == WatchPlan(workouts: []))
    }

    @Test("a library that can't be read sends nothing")
    func unreadableStore() async throws {
        let (_, model) = try await makeModel(failingWorkouts: true)
        let sender = FakeSender()
        await WatchPlanSync(model: model, sender: sender).sync(asOf: day(0))
        #expect(sender.plans.isEmpty)
    }

    @Test("a refused send is reported and tried again on the next sync")
    func failureIsReportedAndRetried() async throws {
        let (_, model) = try await makeModel()
        let sender = FakeSender()
        let sync = WatchPlanSync(model: model, sender: sender)
        sender.failing = true
        await sync.sync(asOf: day(0))
        #expect(sync.lastError != nil)

        sender.failing = false
        await sync.sync(asOf: day(0))
        #expect(sync.lastError == nil)
        #expect(sender.plans.count == 1)
    }

    @Test("the transport's own error is reported too")
    func transportError() async throws {
        let (_, model) = try await makeModel()
        let sender = FakeSender()
        let sync = WatchPlanSync(model: model, sender: sender)
        sender.lastSendError = "session not reachable"
        #expect(sync.lastError == "session not reachable")
    }

    @Test("the Watch schedule sync sends the plan on each run, even with sending to the Workout app off")
    func scheduleSyncSendsPlan() async throws {
        let (store, model) = try await makeModel()
        let run = workout()
        try await store.upsert([run])
        let plan = PlannedActivity(workoutID: run.id, date: day(1))
        try await store.upsert([plan])
        scratch.defaults.set(false, forKey: "watchSync.enabled")
        let sender = FakeSender()
        let sync = WatchScheduleSync(
            model: model, scheduler: FakeScheduler(), defaults: scratch.defaults,
            planSync: WatchPlanSync(model: model, sender: sender))

        await sync.sync(asOf: day(0))

        #expect(sender.plans.first?.workouts.map(\.id) == [plan.id])
    }
}
