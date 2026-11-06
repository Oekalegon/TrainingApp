import Foundation
import TrainingCore

/// A ``RaceStore`` that forwards to an `InMemoryStore` but can be told to fail reading races, for testing that a failed
/// read is reported and does not stop the rest of the Create Plan wizard.
actor FailingRaceReadStore: RaceStore {
    private let base: InMemoryStore
    private var failsReads = false

    struct ReadFailure: Error {}

    init(base: InMemoryStore) {
        self.base = base
    }

    /// Makes ``races(in:)`` throw (or stop throwing).
    func setFailsReads(_ fails: Bool) {
        failsReads = fails
    }

    func races(in range: ClosedRange<Date>) async throws -> [Race] {
        if failsReads { throw ReadFailure() }
        return try await base.races(in: range)
    }

    func race(id: UUID) async throws -> Race? { try await base.race(id: id) }
    func upsert(_ races: [Race]) async throws { try await base.upsert(races) }
    func deleteRace(id: UUID) async throws { try await base.deleteRace(id: id) }
}
