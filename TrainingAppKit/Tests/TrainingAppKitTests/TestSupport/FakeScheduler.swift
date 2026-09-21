import Foundation
import TrainingCore
@testable import TrainingAppKit

/// A `PlannedWorkoutScheduling` double that records every call, standing in for the real
/// `WorkoutKitBridge` (whose `WorkoutScheduler` crashes outside a genuine app bundle).
final actor FakeScheduler: PlannedWorkoutScheduling {
    nonisolated let mintedID = UUID()
    private let scheduleShouldFail: Bool
    private(set) var scheduledPlans: [PlannedActivity] = []
    private(set) var unscheduledPlans: [PlannedActivity] = []
    /// Every scheduler call in order, so a test can pin "schedule the new day before removing the
    /// old one".
    private(set) var callLog: [String] = []

    init(scheduleShouldFail: Bool = false) {
        self.scheduleShouldFail = scheduleShouldFail
    }

    func sync(_ workout: StructuredWorkout) async throws -> UUID {
        mintedID
    }

    func schedule(_ plan: PlannedActivity, workout: StructuredWorkout, calendar: Calendar) async throws {
        if scheduleShouldFail {
            struct SchedulingFailed: Error {}
            throw SchedulingFailed()
        }
        scheduledPlans.append(plan)
        callLog.append("schedule")
    }

    func unschedule(_ plan: PlannedActivity, workout: StructuredWorkout, calendar: Calendar) async throws {
        unscheduledPlans.append(plan)
        callLog.append("unschedule")
    }
}
