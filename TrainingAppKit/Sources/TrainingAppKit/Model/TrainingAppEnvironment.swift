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
    private let importer: any ActivityImporting
    private let athleteStore: any AthleteStore
    private let healthStore: HKHealthStore
    private let athleteReader: HealthKitAthleteReader

    private init(
        model: TrainingModel,
        importer: any ActivityImporting,
        athleteStore: any AthleteStore,
        healthStore: HKHealthStore
    ) {
        self.model = model
        self.importer = importer
        self.athleteStore = athleteStore
        self.healthStore = healthStore
        self.athleteReader = HealthKitAthleteReader(healthStore: healthStore)
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
        await wipeFitnessMetricsCacheIfNeeded(store: store)
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, athleteStore: store, fitnessMetricsCacheStore: store
        )
        let athlete = try await store.athleteProfile() ?? Self.placeholderAthlete()
        let model = TrainingModel(stores: stores, athlete: athlete)
        let healthStore = HKHealthStore()
        // `store` is passed as `activityStore` so a re-imported workout's existing `id` is looked
        // up and reused rather than duplicated — see `HealthKitActivityImporter`'s own doc comment
        // for the bug this avoids.
        let importer = HealthKitActivityImporter(healthStore: healthStore, activityStore: store)
        return TrainingAppEnvironment(
            model: model, importer: importer, athleteStore: store, healthStore: healthStore
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
    private func refreshAthleteProfile(asOf today: Date) async {
        let snapshot = await athleteReader.snapshot(asOf: today)
        let merged = model.athlete.merging(snapshot, asOf: today)
        guard merged != model.athlete else { return }
        model.athlete = merged
        try? await athleteStore.save(merged)
        await model.recompute(asOf: today)
    }

    /// See ``ActivityRefreshing/requestAuthorization()``.
    public func requestAuthorization() async throws {
        try await HealthKitAuthorization.requestAuthorization(for: healthStore)
    }

    /// One-time fix-up for MVP1-59/MVP1-43: `TrainingModel.buildMetricsWithCache` used to
    /// silently cache a bogus all-zero-load recompute result whenever its underlying activity/
    /// plan fetch failed (fixed in TrainingKit#35), which could permanently poison a historical
    /// span of the persisted fitness-metrics cache with near-zero CTL/ATL. That's fixed going
    /// forward, but doesn't repair rows already written under the old behavior — this wipes the
    /// whole cache once (mirroring the same `.distantPast` full-invalidate `buildMetricsWithCache`
    /// already uses internally) so the next `recompute(asOf:)` rebuilds it from scratch with the
    /// fix in place.
    ///
    /// Only marks itself done (via `defaults`) after a *successful* delete — a failure (e.g. a
    /// transient store error right at launch) leaves the flag unset so this retries on the next
    /// launch instead of silently leaving the poisoned cache unrepaired forever, which would just
    /// reintroduce the same "failure treated as success" defect TrainingKit#35 fixed.
    ///
    /// This is one-off data-migration code, not a permanent feature: once it's confirmed to have
    /// run successfully, it and its call site should be deleted (tracked as a follow-up, not kept
    /// indefinitely on the off chance some device hasn't launched yet — this is a single-athlete
    /// app under direct control, not a wide release with unknown update timing).
    ///
    /// - Parameters:
    ///   - store: `any FitnessMetricsCacheStore` rather than the concrete `SwiftDataStore`, so
    ///     this is testable against TrainingKit's `InMemoryStore`.
    ///   - defaults: Injectable for the same reason; defaults to `.standard` for real use.
    nonisolated static func wipeFitnessMetricsCacheIfNeeded(
        store: any FitnessMetricsCacheStore, defaults: UserDefaults = .standard
    ) async {
        guard !defaults.bool(forKey: fitnessMetricsCacheWipeDefaultsKey) else { return }
        do {
            try await store.deleteCachedMetrics(from: .distantPast)
            defaults.set(true, forKey: fitnessMetricsCacheWipeDefaultsKey)
        } catch {
            // Left unset deliberately — see the doc comment above.
        }
    }

    nonisolated static let fitnessMetricsCacheWipeDefaultsKey = "MVP1-59.fitnessMetricsCacheWiped.v1"

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
