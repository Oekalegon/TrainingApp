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

    func send(cues: CueSettings) throws {}

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
    func workout(id: UUID) async throws -> StructuredWorkout? { throw Failure() }
    func upsert(_ workouts: [StructuredWorkout]) async throws {}
    func deleteWorkout(id: UUID) async throws {}
}

/// A workout library that records which workouts were read, to pin that a sync reads only the
/// ones the next 7 days use and never the whole library.
private final class RecordingWorkoutStore: WorkoutLibraryStore, @unchecked Sendable {
    private let base: InMemoryStore
    private(set) var readAll = 0
    private(set) var readIDs: [UUID] = []

    init(_ base: InMemoryStore) { self.base = base }

    func workouts() async throws -> [StructuredWorkout] {
        readAll += 1
        return try await base.workouts()
    }

    func workout(id: UUID) async throws -> StructuredWorkout? {
        readIDs.append(id)
        return try await base.workout(id: id)
    }

    func upsert(_ workouts: [StructuredWorkout]) async throws { try await base.upsert(workouts) }
    func deleteWorkout(id: UUID) async throws { try await base.deleteWorkout(id: id) }
}

@MainActor
@Suite("WatchPlanSync (WATCH-103)")
struct WatchPlanSyncTests {
    private let scratch = ScratchDefaults()

    /// A day offset from a fixed UTC midnight, plus `hours`.
    private func day(_ offset: Int, hours: Double = 8) -> Date {
        Date(timeIntervalSince1970: 1_700_006_400 + Double(offset) * 86400 + hours * 3600)
    }

    private func makeModel(
        failingWorkouts: Bool = false, workoutStore: (any WorkoutLibraryStore)? = nil
    ) async throws -> (InMemoryStore, TrainingModel) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store,
            workoutStore: workoutStore ?? (failingWorkouts ? FailingWorkoutStore() : store),
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

    @Test("a workout with an open step is sent with its expected duration, one with fixed steps without (WATCH-119)")
    func sendsDurationForOpenStep() async throws {
        let (store, model) = try await makeModel()
        let fixed = workout("Fixed")
        let open = StructuredWorkout(
            name: "Open", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .open, target: .heartRateZone(2))])])
        try await store.upsert([fixed, open])
        try await store.upsert([
            PlannedActivity(workoutID: fixed.id, date: day(0)), PlannedActivity(workoutID: open.id, date: day(1))
        ])
        let sender = FakeSender()
        await WatchPlanSync(model: model, sender: sender).sync(asOf: day(0, hours: 6))
        let sent = try #require(sender.plans.last)
        #expect(sent.workouts.first { $0.name == "Fixed" }?.typicalDuration == nil)
        #expect(sent.workouts.first { $0.name == "Open" }?.typicalDuration != nil)
    }

    @Test("the athlete's drain is the median of their latest watch runs' battery drain, and none with fewer than two (WATCH-119)")
    func drainFromActivities() {
        func run(_ day: Int, drop: Double) -> Activity {
            Activity(
                source: .manual, sport: .running, start: self.day(day), duration: 3600,
                batteryStart: 0.9, batteryEnd: 0.9 - drop)
        }
        let plain = Activity(source: .manual, sport: .running, start: day(-4), duration: 3600)
        #expect(WatchPlanSync.drainPerHour(from: [plain, run(-1, drop: 0.1)]) == nil)
        let median = WatchPlanSync.drainPerHour(from: [run(-1, drop: 0.1), plain, run(-2, drop: 0.2), run(-3, drop: 0.15)])
        #expect(abs((median ?? 0) - 0.15) < 1e-9)
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
        #expect(sent.workouts.map(\.name) == ["Easy", "Tempo", "Easy"])
        #expect(sent.workouts.first?.blocks == easy.blocks)
        #expect(sent.sentAt == day(0, hours: 12))
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
        #expect(sender.plans == [WatchPlan(workouts: [], sentAt: day(0))])
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
        await sync.sync(asOf: day(0, hours: 9))
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

        #expect(sender.plans.last?.workouts.isEmpty == true)
    }

    @Test("an unchanged plan is sent again after the refresh interval, so the watch knows it is current")
    func refreshedWhenUnchanged() async throws {
        let (store, model) = try await makeModel()
        let run = workout()
        try await store.upsert([run])
        try await store.upsert([PlannedActivity(workoutID: run.id, date: day(1))])
        let sender = FakeSender()
        let sync = WatchPlanSync(model: model, sender: sender)

        await sync.sync(asOf: day(0, hours: 8))
        await sync.sync(asOf: day(0, hours: 8) + WatchPlanSync.refreshInterval - 1)
        #expect(sender.plans.count == 1)
        await sync.sync(asOf: day(0, hours: 8) + WatchPlanSync.refreshInterval)
        #expect(sender.plans.count == 2)
        #expect(sender.plans.last?.sentAt == day(0, hours: 8) + WatchPlanSync.refreshInterval)
        #expect(sender.plans.last?.workouts == sender.plans.first?.workouts)
    }

    @Test("reads only the workouts the next 7 days use, and never the whole library")
    func readsOnlyTheWindow() async throws {
        let base = InMemoryStore()
        let recording = RecordingWorkoutStore(base)
        let (store, model) = try await makeModel(workoutStore: recording)
        let soon = workout("Soon"), later = workout("Later"), past = workout("Past")
        try await recording.upsert([soon, later, past])
        try await store.upsert([
            PlannedActivity(workoutID: soon.id, date: day(1)),
            PlannedActivity(workoutID: soon.id, date: day(2)),
            PlannedActivity(workoutID: later.id, date: day(30)),
            PlannedActivity(workoutID: past.id, date: day(-30))
        ])
        let sender = FakeSender()

        await WatchPlanSync(model: model, sender: sender).sync(asOf: day(0))

        #expect(recording.readAll == 0)
        #expect(recording.readIDs == [soon.id])
        #expect(sender.plans.first?.workouts.map(\.name) == ["Soon", "Soon"])
    }

    @Test("a library that can't be read sends nothing")
    func unreadableStore() async throws {
        let (store, model) = try await makeModel(failingWorkouts: true)
        try await store.upsert([PlannedActivity(workoutID: UUID(), date: day(1))])
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
