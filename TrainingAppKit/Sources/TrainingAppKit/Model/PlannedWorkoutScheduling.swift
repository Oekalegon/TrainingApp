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
    /// Throws if `workout` can't be put on the Watch (an unsupported sport, goal or alert). The real
    /// bridge throws a ``WatchIncompatibility`` whose message says why, for the planned-workout
    /// cards' warning (MVP2-119) and the sheet's save error.
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

/// Why a workout can't go on the Watch (MVP2-119), thrown by ``PlannedWorkoutScheduling/validate(_:)``:
/// a sentence for the athlete, e.g. "Apple Watch doesn't support this alert for cycling."
public struct WatchIncompatibility: LocalizedError, Equatable, Sendable {
    /// The sentence shown on the planned-workout card and in the sheet's save error.
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }

    public var errorDescription: String? { reason }
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
        do throws(WorkoutKitMappingError) {
            _ = try customWorkout(from: workout)
        } catch {
            throw WatchIncompatibility(reason: Self.reason(for: error, sport: workout.sport))
        }
    }

    /// The athlete-facing sentence for why `customWorkout(from:)` refused a workout (MVP2-119).
    /// Named after the workout's sport rather than the HealthKit activity type in the error, so it
    /// reads like the rest of the app.
    static func reason(for error: WorkoutKitMappingError, sport: Sport) -> String {
        let sportName = sport.displayName.lowercased()
        return switch error {
        case .unsupportedActivity:
            "Apple Watch can't run structured \(sportName) workouts."
        case .unsupportedGoal, .unsupportedGoalForActivity:
            "Apple Watch doesn't support one of this workout's step goals for \(sportName)."
        case .unsupportedAlertForActivity:
            "Apple Watch doesn't support this alert for \(sportName)."
        case .unsupportedWorkoutKind:
            "Apple Watch can't run this kind of workout."
        }
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
    /// device: filter Xcode's console on the "WatchSync" category. Debug level, so it isn't kept
    /// in the device's log store.
    private static let logger = Logger(subsystem: "TrainingApp", category: "WatchSync")

    private static func unsupported() -> WatchSchedulingAuthorization {
        logger.debug("WorkoutScheduler.isSupported is false: scheduling unavailable")
        return .unavailable
    }

    /// `.restricted` (and any state added later) counts as unavailable: the athlete can't change it
    /// in the Watch app, so there's nothing for the banner to tell them.
    private static func authorization(
        from state: WorkoutScheduler.AuthorizationState, after source: String
    ) -> WatchSchedulingAuthorization {
        let description = String(describing: state)
        logger.debug("WorkoutKit authorization after \(source, privacy: .public): \(description, privacy: .public)")
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
