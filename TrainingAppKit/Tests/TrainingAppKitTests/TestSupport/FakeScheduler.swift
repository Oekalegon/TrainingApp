import Foundation
import TrainingCore
@testable import TrainingAppKit

/// A `PlannedWorkoutScheduling` double that records every call, standing in for the real
/// `WorkoutKitBridge` (whose `WorkoutScheduler` crashes outside a genuine app bundle).
final actor FakeScheduler: PlannedWorkoutScheduling {
    private let scheduleShouldFail: Bool
    private let isAuthorized: Bool
    nonisolated let maxScheduledCount: Int
    /// Workouts `validate` rejects, by id.
    nonisolated let invalidWorkoutIDs: Set<UUID>
    private(set) var scheduledPlans: [PlannedActivity] = []
    private(set) var unscheduledPlans: [PlannedActivity] = []
    /// The `planIDs` each `unscheduleAll(except:)` call was given.
    private(set) var keptPlanIDs: [Set<UUID>] = []
    /// Every scheduler call in order, so a test can pin "remove leftovers before scheduling".
    private(set) var callLog: [String] = []

    init(
        scheduleShouldFail: Bool = false,
        isAuthorized: Bool = true,
        maxScheduledCount: Int = 15,
        invalidWorkoutIDs: Set<UUID> = []
    ) {
        self.scheduleShouldFail = scheduleShouldFail
        self.isAuthorized = isAuthorized
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
        return 0
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        callLog.append("authorize")
        return isAuthorized
    }
}
