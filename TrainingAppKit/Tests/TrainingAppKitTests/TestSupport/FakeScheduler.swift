import Foundation
import TrainingCore
@testable import TrainingAppKit

/// A `PlannedWorkoutScheduling` double that records every call, standing in for the real
/// `WorkoutKitBridge` (whose `WorkoutScheduler` crashes outside a genuine app bundle).
final actor FakeScheduler: PlannedWorkoutScheduling {
    private let scheduleShouldFail: Bool
    private var authorization: WatchSchedulingAuthorization
    nonisolated let maxScheduledCount: Int
    /// Workouts `validate` rejects, by id.
    nonisolated let invalidWorkoutIDs: Set<UUID>
    private(set) var scheduledPlans: [PlannedActivity] = []
    private(set) var unscheduledPlans: [PlannedActivity] = []
    /// The `planIDs` each `unscheduleAll(except:)` call was given.
    private(set) var keptPlanIDs: [Set<UUID>] = []
    /// Run once, inside the first `unscheduleAll(except:)` call, so a test can start a second sync
    /// while one is in progress.
    private var duringFirstUnscheduleAll: (@Sendable () async -> Void)?
    /// Every scheduler call in order, so a test can pin "remove leftovers before scheduling".
    private(set) var callLog: [String] = []

    init(
        scheduleShouldFail: Bool = false,
        authorization: WatchSchedulingAuthorization = .authorized,
        maxScheduledCount: Int = 15,
        invalidWorkoutIDs: Set<UUID> = []
    ) {
        self.scheduleShouldFail = scheduleShouldFail
        self.authorization = authorization
        self.maxScheduledCount = maxScheduledCount
        self.invalidWorkoutIDs = invalidWorkoutIDs
    }

    nonisolated func validate(_ workout: StructuredWorkout) throws {
        if invalidWorkoutIDs.contains(workout.id) {
            struct UnsupportedWorkout: Error {}
            throw UnsupportedWorkout()
        }
    }

    /// Logs every attempt, failed or not; only a successful one lands in ``scheduledPlans``.
    func schedule(_ plan: PlannedActivity, workout: StructuredWorkout, calendar: Calendar) async throws {
        callLog.append("schedule")
        if scheduleShouldFail {
            struct SchedulingFailed: Error {}
            throw SchedulingFailed()
        }
        scheduledPlans.append(plan)
    }

    func unschedule(_ plan: PlannedActivity) async {
        unscheduledPlans.append(plan)
        callLog.append("unschedule")
    }

    @discardableResult
    func unscheduleAll(except planIDs: Set<UUID>) async -> Int {
        keptPlanIDs.append(planIDs)
        callLog.append("unscheduleAll")
        if let hook = duringFirstUnscheduleAll {
            duringFirstUnscheduleAll = nil
            await hook()
        }
        return 0
    }

    func setDuringFirstUnscheduleAll(_ hook: @escaping @Sendable () async -> Void) {
        duringFirstUnscheduleAll = hook
    }

    /// Changes the answer later calls get, as when the athlete changes it in the Watch app's Workout settings.
    func setAuthorization(_ authorization: WatchSchedulingAuthorization) {
        self.authorization = authorization
    }

    func requestAuthorizationIfNeeded() async -> WatchSchedulingAuthorization {
        callLog.append("authorize")
        return authorization
    }

    func authorizationStatus() async -> WatchSchedulingAuthorization {
        callLog.append("authorizationStatus")
        return authorization
    }
}
