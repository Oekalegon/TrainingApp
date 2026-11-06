import Foundation
import TrainingCore

/// A ``TrainingPlanStore`` that forwards to an `InMemoryStore` but can be told to fail reading the plans or inserting a
/// new one, for testing the Create Plan wizard's preview and commit failures.
actor FailingTrainingPlanStore: TrainingPlanStore {
    private let base: InMemoryStore
    private var failsReads = false
    private var failsInserts = false

    struct Failure: Error {}

    init(base: InMemoryStore) {
        self.base = base
    }

    /// Makes ``trainingPlans()`` throw (or stop throwing).
    func setFailsReads(_ fails: Bool) {
        failsReads = fails
    }

    /// Makes ``insertTrainingPlan(_:cycles:plannedActivities:)`` throw (or stop throwing).
    func setFailsInserts(_ fails: Bool) {
        failsInserts = fails
    }

    func trainingPlans() async throws -> [TrainingPlan] {
        if failsReads { throw Failure() }
        return try await base.trainingPlans()
    }

    func trainingPlan(id: UUID) async throws -> TrainingPlan? { try await base.trainingPlan(id: id) }

    func upsertTrainingPlan(_ plan: TrainingPlan, cancelingActivePlanOn date: Date?) async throws {
        try await base.upsertTrainingPlan(plan, cancelingActivePlanOn: date)
    }

    func adoptUnassigned(intoActivePlanOrNew newPlan: TrainingPlan) async throws -> Bool {
        try await base.adoptUnassigned(intoActivePlanOrNew: newPlan)
    }

    func insertTrainingPlan(_ plan: TrainingPlan, cycles: [TrainingCycle], plannedActivities: [PlannedActivity]) async throws {
        if failsInserts { throw Failure() }
        try await base.insertTrainingPlan(plan, cycles: cycles, plannedActivities: plannedActivities)
    }

    func deleteTrainingPlan(id: UUID) async throws { try await base.deleteTrainingPlan(id: id) }
}
