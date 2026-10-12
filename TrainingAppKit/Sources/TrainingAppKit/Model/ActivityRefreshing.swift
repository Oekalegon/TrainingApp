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

    /// Runs one `TrainingModel.resyncActivities(from:asOf:)` cycle — a full re-import rather than
    /// an incremental one, for the athlete screen's "Force Full Resync" action (design doc §2.3).
    func resyncActivities(asOf today: Date) async throws

    /// Requests whatever permission the underlying source needs before ``refreshActivities(asOf:)``
    /// can return real data — e.g. the HealthKit read-authorization prompt, for the empty-state
    /// "Connect Health data" button (design doc §2.1).
    func requestAuthorization() async throws

    /// Whether the source has types the athlete has not been asked about yet (MVP2-146): an install
    /// that connected Health before the app began reading distance has never been asked for it, and
    /// nothing else would ask. `false` when everything has been answered, whatever the answers were.
    func hasUnansweredPermissions() async -> Bool
}

extension ActivityRefreshing {
    /// Sources that can't have unanswered permissions (tests, previews) report none.
    public func hasUnansweredPermissions() async -> Bool { false }
}
