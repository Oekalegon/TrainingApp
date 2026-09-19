import Foundation
import TrainingCore
#if canImport(WorkoutKit)
import TrainingWorkoutKit
#endif

/// Abstracts `WorkoutKitBridge`'s sync/schedule pair so ``PlannedWorkoutSheetViewModel`` can be
/// tested without touching the real `WorkoutScheduler` — which requires a genuine app bundle
/// context and crashes (`unable to determine bundle id`) when called from a SPM test executable.
public protocol PlannedWorkoutScheduling: Sendable {
    func sync(_ workout: StructuredWorkout) async throws -> UUID
    func schedule(_ plan: PlannedActivity, workout: StructuredWorkout, calendar: Calendar) async throws
    /// Removes `plan`'s scheduled entry for `plan.date` — used when editing moves a plan to another
    /// day, so the old date doesn't keep showing on the Watch.
    func unschedule(_ plan: PlannedActivity, workout: StructuredWorkout, calendar: Calendar) async throws
}

#if canImport(WorkoutKit)
extension WorkoutKitBridge: PlannedWorkoutScheduling {}
#endif
