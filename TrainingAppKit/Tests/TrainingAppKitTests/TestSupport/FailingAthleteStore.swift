import Foundation
import TrainingCore

/// An ``AthleteStore`` that forwards to an `InMemoryStore` but can be told to fail saving the
/// profile, for testing that a failed edit changes nothing.
actor FailingAthleteStore: AthleteStore {
    private let base: InMemoryStore
    private var failsSaves = false

    struct SaveFailure: Error {}

    init(base: InMemoryStore) {
        self.base = base
    }

    /// Makes ``save(_:)`` throw (or stop throwing).
    func setFailsSaves(_ fails: Bool) {
        failsSaves = fails
    }

    func athleteProfile() async throws -> AthleteProfile? { try await base.athleteProfile() }

    func save(_ profile: AthleteProfile) async throws {
        if failsSaves { throw SaveFailure() }
        try await base.save(profile)
    }

    func importAnchor() async throws -> ImportAnchor? { try await base.importAnchor() }
    func saveImportAnchor(_ anchor: ImportAnchor?) async throws { try await base.saveImportAnchor(anchor) }
}
