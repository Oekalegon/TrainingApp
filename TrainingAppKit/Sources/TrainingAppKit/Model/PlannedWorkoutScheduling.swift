import Foundation
import TrainingCore
#if canImport(WorkoutKit)
import TrainingWorkoutKit
import WorkoutKit
#endif

/// Abstracts `WorkoutKitBridge`'s per-plan scheduling (MVP2-55) so ``PlannedWorkoutSheetViewModel``,
/// ``PlannedWorkoutDetailViewModel`` and ``WatchScheduleSync`` can be tested without touching the
/// real `WorkoutScheduler` — which requires a genuine app bundle context and crashes (`unable to
/// determine bundle id`) when called from a SPM test executable.
///
/// Each Watch entry belongs to one plan and carries that plan's id, so nothing about it is stored in
/// the app: scheduling a plan again replaces its entry, wherever it was.
public protocol PlannedWorkoutScheduling: Sendable {
    /// Throws if `workout` can't be put on the Watch (an unsupported sport, goal or alert).
    func validate(_ workout: StructuredWorkout) throws

    /// Puts `workout` on the Watch on `plan`'s day, replacing whatever was scheduled for `plan`
    /// before — so a moved plan or an edited workout needs just this call. Calling it again for an
    /// unchanged plan is a no-op.
    func schedule(_ plan: PlannedActivity, workout: StructuredWorkout, calendar: Calendar) async throws

    /// Removes `plan`'s entry from the Watch, for when the plan is deleted.
    func unschedule(_ plan: PlannedActivity) async

    /// Removes every entry whose plan id isn't in `planIDs`, returning how many it removed.
    @discardableResult
    func unscheduleAll(except planIDs: Set<UUID>) async -> Int

    /// Whether the app may schedule workouts, asking the athlete the first time. `false` when the
    /// device doesn't support scheduled workouts or the athlete declined.
    func requestAuthorizationIfNeeded() async -> Bool

    /// Whether the app may schedule workouts, without asking.
    func isAuthorized() async -> Bool

    /// How many entries the app may hold on the Watch at once.
    var maxScheduledCount: Int { get }
}

/// Where the app's real ``PlannedWorkoutScheduling`` comes from.
public enum PlannedWorkoutSchedulers {
    /// A `WorkoutKitBridge` where WorkoutKit is available, `nil` otherwise. The default for every
    /// view model and ``WatchScheduleSync``; tests pass a fake or `nil` instead.
    public static var live: (any PlannedWorkoutScheduling)? {
        #if canImport(WorkoutKit)
        WorkoutKitBridge()
        #else
        nil
        #endif
    }
}

#if canImport(WorkoutKit)
extension WorkoutKitBridge: PlannedWorkoutScheduling {
    public func validate(_ workout: StructuredWorkout) throws {
        _ = try customWorkout(from: workout)
    }

    public func requestAuthorizationIfNeeded() async -> Bool {
        guard WorkoutScheduler.isSupported else { return false }
        switch await WorkoutKitAuthorization.state {
        case .authorized:
            return true
        case .notDetermined:
            return await WorkoutKitAuthorization.requestAuthorization() == .authorized
        default:
            return false
        }
    }

    public func isAuthorized() async -> Bool {
        guard WorkoutScheduler.isSupported else { return false }
        return await WorkoutKitAuthorization.state == .authorized
    }

    public var maxScheduledCount: Int { WorkoutScheduler.maxAllowedScheduledWorkoutCount }
}
#endif
