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
    private let importer: any ActivityImporting
    private let healthStore: HKHealthStore

    private init(model: TrainingModel, importer: any ActivityImporting, healthStore: HKHealthStore) {
        self.model = model
        self.importer = importer
        self.healthStore = healthStore
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
            cycleStore: store, athleteStore: store
        )
        let athlete = try await store.athleteProfile() ?? Self.placeholderAthlete()
        let model = TrainingModel(stores: stores, athlete: athlete)
        let healthStore = HKHealthStore()
        // `store` is passed as `activityStore` so a re-imported workout's existing `id` is looked
        // up and reused rather than duplicated — see `HealthKitActivityImporter`'s own doc comment
        // for the bug this avoids.
        let importer = HealthKitActivityImporter(healthStore: healthStore, activityStore: store)
        return TrainingAppEnvironment(model: model, importer: importer, healthStore: healthStore)
    }

    /// See ``ActivityRefreshing/refreshActivities(asOf:)``.
    public func refreshActivities(asOf today: Date) async throws {
        try await model.importActivities(from: importer, asOf: today)
    }

    /// See ``ActivityRefreshing/requestAuthorization()``.
    public func requestAuthorization() async throws {
        try await HealthKitAuthorization.requestAuthorization(for: healthStore)
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
