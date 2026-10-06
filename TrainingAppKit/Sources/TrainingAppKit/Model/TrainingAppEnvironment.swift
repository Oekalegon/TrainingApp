import Foundation
import TrainingCore
import TrainingHealthKit
import TrainingPersistence
import HealthKit

/// Builds and owns the single `TrainingModel` this app runs on, plus the HealthKit-backed
/// ``ActivityRefreshing`` pull-to-refresh calls into.
///
/// Single-athlete only, per this app's MVP 1 scope (design doc §3.1) — there is no roster to
/// choose between, so exactly one `TrainingModel` for the app's lifetime. Views/view models
/// should depend on ``ActivityRefreshing`` (and, where they need it, `TrainingModel` directly)
/// rather than this concrete type, so they stay testable against `InMemoryStore` without
/// HealthKit or CloudKit involved.
@MainActor
public final class TrainingAppEnvironment: ActivityRefreshing {
    public let model: TrainingModel
    /// Keeps the Watch's scheduled workouts in step with the plans (MVP2-55); `nil` where
    /// WorkoutKit isn't available.
    public let watchSync: WatchScheduleSync?
    private let importer: any ActivityImporting
    private let healthStore: HKHealthStore
    private let athleteReader: HealthKitAthleteReader
    /// Imports workouts as soon as Health has them (MVP2-121); see ``startWorkoutObservation()``.
    private lazy var workoutBackgroundImport = WorkoutBackgroundImport(
        observer: HealthKitWorkoutObserver(healthStore: healthStore),
        onNewWorkouts: { [weak self] in await self?.importArrivedWorkouts() }
    )
    /// The one environment the app runs on, shared by the app delegate (which starts workout
    /// observation at launch, also when HealthKit launches the app in the background) and the UI.
    private static var sharedTask: Task<TrainingAppEnvironment, Error>?

    private init(
        model: TrainingModel,
        importer: any ActivityImporting,
        healthStore: HKHealthStore
    ) {
        self.model = model
        self.watchSync = WatchScheduleSync.live(model: model)
        self.importer = importer
        self.healthStore = healthStore
        self.athleteReader = HealthKitAthleteReader(healthStore: healthStore)
    }

    /// The environment this app instance runs on, created on first use and shared afterwards.
    ///
    /// Both the app delegate and the launch view ask for it, and two environments would open the
    /// store twice. A failed creation isn't kept, so the next call tries again.
    ///
    /// - Throws: Whatever ``make()`` throws.
    public static func shared() async throws -> TrainingAppEnvironment {
        if let sharedTask {
            return try await sharedTask.value
        }
        let task = Task { try await make() }
        sharedTask = task
        do {
            return try await task.value
        } catch {
            sharedTask = nil
            throw error
        }
    }

    /// Creates the environment this app instance runs on.
    ///
    /// The CloudKit container used is whichever `com.apple.developer.icloud-container-identifiers`
    /// entry the app target's entitlements declare — `TrainingPersistenceContainer` itself has no
    /// opinion on the identifier (see `docs/design/trainingApp-design.md` §3.2).
    ///
    /// - Throws: Whatever `TrainingPersistenceContainer.make()` or the store throws.
    public static func make() async throws -> TrainingAppEnvironment {
        let container = try TrainingPersistenceContainer.make()
        let store = SwiftDataStore(modelContainer: container)
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store, fitnessMetricsCacheStore: store
        )
        let athlete = try await store.athleteProfile() ?? Self.placeholderAthlete()
        let model = TrainingModel(stores: stores, athlete: athlete)
        let healthStore = HKHealthStore()
        // `store` is passed as `activityStore` so a re-imported workout's existing `id` is looked
        // up and reused rather than duplicated — see `HealthKitActivityImporter`'s own doc comment
        // for the bug this avoids.
        let importer = HealthKitActivityImporter(healthStore: healthStore, activityStore: store)
        return TrainingAppEnvironment(
            model: model, importer: importer, healthStore: healthStore
        )
    }

    /// See ``ActivityRefreshing/refreshActivities(asOf:)``.
    ///
    /// Also refreshes the athlete's biometrics from HealthKit (design doc §2.3's expectation that
    /// this screen shows real imported data) — see ``refreshAthleteProfile(asOf:)``.
    public func refreshActivities(asOf today: Date) async throws {
        try await model.importActivities(from: importer, asOf: today)
        await refreshAthleteProfile(asOf: today)
    }

    /// See ``ActivityRefreshing/resyncActivities(asOf:)``.
    public func resyncActivities(asOf today: Date) async throws {
        try await model.resyncActivities(from: importer, asOf: today)
        await refreshAthleteProfile(asOf: today)
    }

    /// Reads a `HealthKitAthleteSnapshot` and merges it into `model.athlete`, persisting the
    /// result if anything actually changed. Errors are swallowed — `HealthKitAthleteReader`
    /// itself already treats a denied/missing data type as `nil` per field rather than throwing,
    /// so a save failure here shouldn't take down `refreshActivities(asOf:)`, which just
    /// successfully imported real activity data.
    ///
    /// Goes through `TrainingModel.updateAthlete(asOf:_:)` (MVP2-101), so the merge runs on
    /// whatever profile is current when its turn comes in TrainingKit's queue. Merging into a copy
    /// read before the save and assigning it afterwards could drop a max heart rate the athlete
    /// accepted in the meantime (MVP2-56), or be dropped by it.
    private func refreshAthleteProfile(asOf today: Date) async {
        let snapshot = await athleteReader.snapshot(asOf: today)
        try? await model.updateAthlete(asOf: today) { $0.merging(snapshot, asOf: today) }
    }

    /// Starts importing new workouts as soon as Health has them, also while the app is closed
    /// (MVP2-121). Safe to call again: once it's running, later calls do nothing, and a call after a
    /// failed start (HealthKit not authorized yet) tries again.
    ///
    /// Call it on every launch, early — HealthKit wakes the app in the background only for a query
    /// the new process has registered — and again once the athlete grants access.
    public func startWorkoutObservation() async {
        await workoutBackgroundImport.start()
    }

    /// What a "new workout" notification does: see ``ArrivedWorkoutImport/run(refresher:watchSync:asOf:notify:)``.
    /// The UI is told through ``Foundation/Notification/Name/trainingAppDidImportWorkouts``.
    func importArrivedWorkouts(asOf today: Date = .now) async {
        await ArrivedWorkoutImport.run(refresher: self, watchSync: watchSync, asOf: today) {
            NotificationCenter.default.post(name: .trainingAppDidImportWorkouts, object: nil)
        }
    }

    /// See ``ActivityRefreshing/requestAuthorization()``.
    ///
    /// Then starts workout observation (MVP2-121): background delivery can only be enabled once
    /// HealthKit access has been granted, so the launch-time start fails on a first run.
    public func requestAuthorization() async throws {
        try await HealthKitAuthorization.requestAuthorization(for: healthStore)
        await startWorkoutObservation()
    }

    /// A blank athlete profile used until the first HealthKit import populates real biometrics.
    nonisolated static func placeholderAthlete() -> AthleteProfile {
        AthleteProfile(
            sex: .unspecified,
            paceModel: PaceModel(thresholdPaceSecondsPerKilometer: 300),
            timeZone: .current,
            heartRateZoneHistory: []
        )
    }
}
