import Foundation
import HealthKit
import os

/// The live ``WorkoutChangeObserving``: an `HKObserverQuery` on workouts, plus background delivery
/// at `.immediate` frequency so HealthKit launches the app when the Watch (or anything else) saves
/// one (MVP2-121).
///
/// Needs the `com.apple.developer.healthkit.background-delivery` entitlement, and must be started on
/// every launch, early: HealthKit wakes the app in the background and only then delivers to a query
/// the new process has registered. HealthKit also calls the handler once right after a query is
/// registered, so every launch runs one extra (incremental, idempotent) import; that is expected.
///
/// Keeps its query so a start that fails (e.g. before HealthKit access is granted) stops it again:
/// a retry would otherwise run a second query, and every notification would import twice.
final class HealthKitWorkoutObserver: WorkoutChangeObserving, @unchecked Sendable {
    private static let logger = Logger(subsystem: "TrainingApp", category: "WorkoutObserver")

    /// HealthKit's completion handler isn't marked `Sendable`, but it's documented as callable from
    /// any thread, once.
    private struct Completion: @unchecked Sendable {
        let call: () -> Void
    }

    private let healthStore: HKHealthStore
    private let lock = NSLock()
    private var query: HKObserverQuery?

    init(healthStore: HKHealthStore) {
        self.healthStore = healthStore
    }

    func start(onChange: @escaping @Sendable (_ done: @escaping @Sendable () -> Void) -> Void) async throws {
        let type = HKObjectType.workoutType()
        let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completionHandler, error in
            let completion = Completion(call: completionHandler)
            if let error {
                Self.logger.error("Workout observer failed: \(String(describing: error), privacy: .public)")
                completion.call()
                return
            }
            onChange { completion.call() }
        }
        replaceQuery(with: query)
        healthStore.execute(query)
        do {
            try await healthStore.enableBackgroundDelivery(for: type, frequency: .immediate)
        } catch {
            replaceQuery(with: nil)
            throw error
        }
    }

    /// Stops whatever query is running and remembers `newQuery` (not yet executed) in its place.
    private func replaceQuery(with newQuery: HKObserverQuery?) {
        let old = lock.withLock {
            let old = query
            query = newQuery
            return old
        }
        if let old {
            healthStore.stop(old)
        }
    }
}
