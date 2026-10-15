import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

/// MVP2-121: new workouts are imported as soon as Health has them.
@MainActor
@Suite("WorkoutBackgroundImport")
struct WorkoutBackgroundImportTests {
    /// Records what the import trigger asked for, and lets a test fire notifications.
    private final class FakeObserver: WorkoutChangeObserving, @unchecked Sendable {
        struct Boom: Error {}
        private let lock = NSLock()
        private var handler: (@Sendable (_ done: @escaping @Sendable () -> Void) -> Void)?
        private(set) var startCount = 0
        var failures: Int

        init(failingStarts: Int = 0) {
            failures = failingStarts
        }

        func start(onChange: @escaping @Sendable (_ done: @escaping @Sendable () -> Void) -> Void) async throws {
            let shouldFail = lock.withLock {
                startCount += 1
                let shouldFail = failures > 0
                if shouldFail { failures -= 1 } else { handler = onChange }
                return shouldFail
            }
            if shouldFail { throw Boom() }
        }

        /// Fires one notification and returns once the trigger reports `done`.
        func fire() async {
            let handler = lock.withLock { self.handler }
            await withCheckedContinuation { continuation in
                handler?({ continuation.resume() })
            }
        }
    }

    @Test("a notification runs the import, and reports done only after it finished")
    func notificationRunsImportBeforeDone() async {
        let observer = FakeObserver()
        var events: [String] = []
        let trigger = WorkoutBackgroundImport(observer: observer) {
            events.append("import started")
            await Task.yield()
            events.append("import finished")
        }
        await trigger.start()

        await observer.fire()
        events.append("done")

        #expect(events == ["import started", "import finished", "done"])
    }

    @Test("every notification runs the import")
    func everyNotificationImports() async {
        let observer = FakeObserver()
        var imports = 0
        let trigger = WorkoutBackgroundImport(observer: observer) { imports += 1 }
        await trigger.start()

        await observer.fire()
        await observer.fire()

        #expect(imports == 2)
    }

    @Test("starting twice registers the observer once")
    func startIsIdempotent() async {
        let observer = FakeObserver()
        let trigger = WorkoutBackgroundImport(observer: observer) {}

        await trigger.start()
        await trigger.start()

        #expect(observer.startCount == 1)
        #expect(trigger.isStarted)
    }

    @Test("a failed start (e.g. HealthKit not authorized yet) can be retried")
    func failedStartRetries() async {
        let observer = FakeObserver(failingStarts: 1)
        let trigger = WorkoutBackgroundImport(observer: observer) {}

        await trigger.start()
        #expect(!trigger.isStarted)

        await trigger.start()
        #expect(trigger.isStarted)
        #expect(observer.startCount == 2)
    }

    @Test("the UI refreshes its caches after an import it didn't run: a new workout's heart-rate histogram shows")
    func activitiesImportedElsewhereRefreshesCaches() async throws {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC", restingHeartRateBPM: 50, maxHeartRateBPM: 190)
        let model = TrainingModel(stores: stores, athlete: athlete)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: now)
        let weekStart = viewModel.displayedWeekStart
        await viewModel.load(asOf: weekStart)
        #expect(viewModel.heartRateHistogram(for: weekStart).bins.isEmpty)

        // Imported behind the view model's back, as the background import does.
        let samples = stride(from: 0, through: 600, by: 30).map {
            HeartRateSample(time: weekStart.addingTimeInterval(TimeInterval($0)), bpm: 160)
        }
        try await store.upsert([Activity(source: .manual, sport: .running, start: weekStart, duration: 600, heartRate: samples)])
        try await model.load(in: viewModel.chartRange, asOf: weekStart)

        await viewModel.activitiesImportedElsewhere(asOf: weekStart)

        #expect(viewModel.heartRateHistogram(for: weekStart).bins.contains { $0.bpm == 160 })
    }
}

/// MVP2-121: the import, then the awaited Watch sync, then the UI notification.
@MainActor
@Suite("ArrivedWorkoutImport")
struct ArrivedWorkoutImportTests {
    private final class RecordingRefresher: ActivityRefreshing {
        struct Boom: Error {}
        var events: [String] = []
        var shouldThrow = false

        func refreshActivities(asOf today: Date) async throws {
            events.append("import")
            if shouldThrow { throw Boom() }
        }
        func resyncActivities(asOf today: Date) async throws {}
        func requestAuthorization() async throws {}
    }

    private func makeWatchSync(scheduler: FakeScheduler) -> WatchScheduleSync {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        let model = TrainingModel(stores: stores, athlete: AthleteProfile.fixture(timeZoneIdentifier: "UTC"))
        let defaults = UserDefaults(suiteName: "ArrivedWorkoutImportTests-\(UUID())")!
        return WatchScheduleSync(model: model, scheduler: scheduler, defaults: defaults)
    }

    @Test("imports, then finishes the Watch sync, then notifies, in that order")
    func importThenSyncThenNotify() async {
        let refresher = RecordingRefresher()
        let scheduler = FakeScheduler()
        var syncRanBeforeNotify = false

        await ArrivedWorkoutImport.run(
            refresher: refresher, watchSync: makeWatchSync(scheduler: scheduler), asOf: .now
        ) {
            refresher.events.append("notify")
            syncRanBeforeNotify = !(await scheduler.callLog.isEmpty)
        }

        #expect(refresher.events == ["import", "notify"])
        #expect(syncRanBeforeNotify)
    }

    @Test("a failed import still syncs the Watch and notifies")
    func failedImportStillSyncsAndNotifies() async {
        let refresher = RecordingRefresher()
        refresher.shouldThrow = true
        let scheduler = FakeScheduler()
        var notified = false

        await ArrivedWorkoutImport.run(
            refresher: refresher, watchSync: makeWatchSync(scheduler: scheduler), asOf: .now
        ) { notified = true }

        #expect(notified)
        #expect(!(await scheduler.callLog.isEmpty))
    }

    @Test("without WorkoutKit it just imports and notifies")
    func noWatchSync() async {
        let refresher = RecordingRefresher()

        await ArrivedWorkoutImport.run(refresher: refresher, watchSync: nil, asOf: .now) {
            refresher.events.append("notify")
        }

        #expect(refresher.events == ["import", "notify"])
    }
}
