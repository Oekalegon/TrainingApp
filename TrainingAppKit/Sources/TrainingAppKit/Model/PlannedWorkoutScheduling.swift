import Foundation
import TrainingCore
#if canImport(WorkoutKit)
import OSLog
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

    /// Whether the app may schedule workouts, asking the athlete the first time.
    func requestAuthorizationIfNeeded() async -> WatchSchedulingAuthorization

    /// Whether the app may schedule workouts, without asking.
    func authorizationStatus() async -> WatchSchedulingAuthorization

    /// How many entries the app may hold on the Watch at once.
    var maxScheduledCount: Int { get }
}

/// Whether the app may put planned workouts on the Watch (MVP2-55, MVP2-117).
public enum WatchSchedulingAuthorization: Sendable, Equatable {
    /// The athlete allowed it.
    case authorized
    /// The athlete hasn't been asked yet.
    case notDetermined
    /// The athlete declined, at the prompt or later in the Watch app's Workout settings. iOS doesn't
    /// ask again; only those settings can turn it back on.
    case denied
    /// The device can't schedule workouts, or a restriction the athlete can't lift prevents it.
    case unavailable

    /// Whether the app may schedule workouts.
    public var isAuthorized: Bool { self == .authorized }
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

    public func requestAuthorizationIfNeeded() async -> WatchSchedulingAuthorization {
        guard WorkoutScheduler.isSupported else { return Self.unsupported() }
        let state = await WorkoutKitAuthorization.state
        guard state == .notDetermined else { return Self.authorization(from: state, after: "check") }
        return Self.authorization(from: await WorkoutKitAuthorization.requestAuthorization(), after: "prompt")
    }

    public func authorizationStatus() async -> WatchSchedulingAuthorization {
        guard WorkoutScheduler.isSupported else { return Self.unsupported() }
        return Self.authorization(from: await WorkoutKitAuthorization.state, after: "check")
    }

    /// Logs what WorkoutKit reported, so a banner that doesn't show (MVP2-117) can be traced on a
    /// device: filter Console or Xcode's log on the "WatchSync" category.
    private static let logger = Logger(subsystem: "TrainingApp", category: "WatchSync")

    private static func unsupported() -> WatchSchedulingAuthorization {
        logger.notice("WorkoutScheduler.isSupported is false: scheduling unavailable")
        return .unavailable
    }

    /// `.restricted` (and any state added later) counts as unavailable: the athlete can't change it
    /// in the Watch app, so there's nothing for the banner to tell them.
    private static func authorization(
        from state: WorkoutScheduler.AuthorizationState, after source: String
    ) -> WatchSchedulingAuthorization {
        let description = String(describing: state)
        logger.notice("WorkoutKit authorization after \(source, privacy: .public): \(description, privacy: .public)")
        return switch state {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        case .denied: .denied
        default: .unavailable
        }
    }

    public var maxScheduledCount: Int { WorkoutScheduler.maxAllowedScheduledWorkoutCount }
}
#endif
