import Foundation
import os

/// Imports new workouts as soon as Health has them, including while the app is closed (MVP2-121).
///
/// Starts a ``WorkoutChangeObserving`` once, and runs `onNewWorkouts` for each notification. The
/// observer is told the work is done only afterwards, so the system keeps the app awake for the
/// import and the Watch sync that follows it.
@MainActor
public final class WorkoutBackgroundImport {
    private static let logger = Logger(subsystem: "TrainingApp", category: "WorkoutImport")

    private let observer: any WorkoutChangeObserving
    private let onNewWorkouts: @MainActor () async -> Void
    /// Whether the observer is running. Stays `false` after a failed start, so the next ``start()``
    /// tries again (e.g. once HealthKit access has been granted).
    private(set) var isStarted = false
    private var isStarting = false

    /// - Parameters:
    ///   - observer: Where notifications come from.
    ///   - onNewWorkouts: Runs for every notification; typically an import, then a Watch sync.
    init(observer: any WorkoutChangeObserving, onNewWorkouts: @escaping @MainActor () async -> Void) {
        self.observer = observer
        self.onNewWorkouts = onNewWorkouts
    }

    /// Starts observing, unless it already is or a start is in progress. A failure is logged and
    /// leaves ``isStarted`` `false`, so a later call retries.
    public func start() async {
        guard !isStarted, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        do {
            try await observer.start { [weak self] done in
                Task { @MainActor in
                    await self?.onNewWorkouts()
                    done()
                }
            }
            isStarted = true
        } catch {
            Self.logger.error("Starting workout observation failed: \(String(describing: error), privacy: .public)")
        }
    }
}
