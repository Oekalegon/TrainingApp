import Foundation

/// Something that can run a fresh HealthKit import against the app's `TrainingModel`.
///
/// A narrow seam between `WeekViewModel` and `TrainingAppEnvironment`'s concrete HealthKit/
/// CloudKit wiring, so `WeekViewModel` stays testable against `InMemoryStore` — a test substitutes
/// a stub conforming to this instead of needing real HealthKit/CloudKit (design doc §4).
@MainActor
public protocol ActivityRefreshing {
    /// Runs one `TrainingModel.importActivities(from:asOf:)` cycle.
    func refreshActivities(asOf today: Date) async throws

    /// Requests whatever permission the underlying source needs before ``refreshActivities(asOf:)``
    /// can return real data — e.g. the HealthKit read-authorization prompt, for the empty-state
    /// "Connect Health data" button (design doc §2.1).
    func requestAuthorization() async throws
}
