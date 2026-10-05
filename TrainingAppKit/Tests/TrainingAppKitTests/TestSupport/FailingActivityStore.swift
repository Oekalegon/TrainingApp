import Foundation
import TrainingCore

/// An ``ActivityStore`` that forwards to an `InMemoryStore` but can be told to fail reads by date
/// range, for testing what a view model does when the store can't be read.
actor FailingActivityStore: ActivityStore {
    private let base: InMemoryStore
    private var failsRangeReads = false

    struct ReadFailure: Error {}

    init(base: InMemoryStore) {
        self.base = base
    }

    /// Makes ``activities(in:)`` throw (or stop throwing).
    func setFailsRangeReads(_ fails: Bool) {
        failsRangeReads = fails
    }

    func activities(in range: ClosedRange<Date>) async throws -> [Activity] {
        if failsRangeReads { throw ReadFailure() }
        return try await base.activities(in: range)
    }

    func upsert(_ activities: [Activity]) async throws { try await base.upsert(activities) }
    func activity(source: ActivitySource) async throws -> Activity? { try await base.activity(source: source) }
    func activity(id: UUID) async throws -> Activity? { try await base.activity(id: id) }
    func activities(ids: [UUID]) async throws -> [UUID: Activity] { try await base.activities(ids: ids) }
    func deleteActivity(source: ActivitySource) async throws { try await base.deleteActivity(source: source) }
    func deleteActivity(id: UUID) async throws { try await base.deleteActivity(id: id) }
    func tombstonedSources(among sources: [ActivitySource]) async throws -> Set<ActivitySource> {
        try await base.tombstonedSources(among: sources)
    }
    func deduplicateActivities() async throws -> [Activity] { try await base.deduplicateActivities() }
    func saveJoin(_ merged: Activity, components: [UUID], replacing replacedJoinIDs: [UUID]) async throws {
        try await base.saveJoin(merged, components: components, replacing: replacedJoinIDs)
    }
    func joinedActivity(containing componentID: UUID) async throws -> Activity? {
        try await base.joinedActivity(containing: componentID)
    }
    func components(ofJoinedActivity id: UUID) async throws -> [Activity] {
        try await base.components(ofJoinedActivity: id)
    }
    func unjoinActivity(id: UUID) async throws { try await base.unjoinActivity(id: id) }
}
