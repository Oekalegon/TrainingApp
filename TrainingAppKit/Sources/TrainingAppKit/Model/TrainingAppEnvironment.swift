import TrainingCore
import TrainingPersistence

/// Builds the single `TrainingModel` this app runs on: one `ModelContainer`/`SwiftDataStore`
/// backed by CloudKit, and the athlete profile already on record (or a placeholder, pending
/// HealthKit import filling it in on first sync).
///
/// Single-athlete only, per this app's MVP 1 scope (design doc §3.1) — there is no roster to
/// choose between, so exactly one `TrainingModel` for the app's lifetime.
public enum TrainingAppEnvironment {
    /// Creates the `TrainingModel` this app instance runs on.
    ///
    /// The CloudKit container used is whichever `com.apple.developer.icloud-container-identifiers`
    /// entry the app target's entitlements declare — `TrainingPersistenceContainer` itself has no
    /// opinion on the identifier (see `docs/design/trainingApp-design.md` §3.2).
    ///
    /// - Throws: Whatever `TrainingPersistenceContainer.make()` or the store throws.
    @MainActor
    public static func makeModel() async throws -> TrainingModel {
        let container = try TrainingPersistenceContainer.make()
        let store = SwiftDataStore(modelContainer: container)
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, athleteStore: store
        )
        let athlete = try await store.athleteProfile() ?? Self.placeholderAthlete()
        return TrainingModel(stores: stores, athlete: athlete)
    }

    /// A blank athlete profile used until the first HealthKit import populates real biometrics.
    static func placeholderAthlete() -> AthleteProfile {
        AthleteProfile(
            sex: .unspecified,
            paceModel: PaceModel(thresholdPaceSecondsPerKilometer: 300),
            timeZone: .current,
            heartRateZoneHistory: []
        )
    }
}
