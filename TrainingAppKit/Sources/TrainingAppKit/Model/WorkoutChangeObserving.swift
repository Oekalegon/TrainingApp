import Foundation

/// Something that tells the app when new workouts have reached Health, even while the app isn't
/// running (MVP2-121) — the seam between ``WorkoutBackgroundImport`` and HealthKit's observer query,
/// so the import trigger can be tested without HealthKit.
public protocol WorkoutChangeObserving: Sendable {
    /// Starts watching for new workouts and asks the system to wake the app when one arrives.
    ///
    /// - Parameter onChange: Called on each notification, from any thread. The observer must be
    ///   told when the work is finished by calling `done`: HealthKit keeps the app awake only until
    ///   then, and stops delivering if it's never called.
    /// - Throws: When the system refuses to start the delivery, e.g. HealthKit isn't authorized yet
    ///   or the background-delivery entitlement is missing. Calling again later retries.
    func start(onChange: @escaping @Sendable (_ done: @escaping @Sendable () -> Void) -> Void) async throws
}
