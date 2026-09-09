import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@Suite("TrainingAppEnvironment")
struct TrainingAppEnvironmentTests {
    @Test("placeholderAthlete() is a usable, if blank, profile")
    func placeholderAthleteIsUsable() {
        let athlete = TrainingAppEnvironment.placeholderAthlete()

        #expect(athlete.sex == .unspecified)
        #expect(athlete.heartRateZoneHistory.isEmpty)
        #expect(athlete.name.isEmpty)
    }

    @Test("wipeFitnessMetricsCacheIfNeeded(store:defaults:) deletes cached metrics and marks itself done")
    func wipeDeletesCacheAndSetsFlag() async throws {
        let store = InMemoryStore()
        let defaults = Self.makeDefaults()
        try await store.upsert([FitnessMetrics.stub(day: .distantPast)])

        await TrainingAppEnvironment.wipeFitnessMetricsCacheIfNeeded(store: store, defaults: defaults)

        let remaining = try await store.cachedMetrics(in: .distantPast...Date())
        #expect(remaining.isEmpty)
        #expect(defaults.bool(forKey: TrainingAppEnvironment.fitnessMetricsCacheWipeDefaultsKey))
    }

    @Test("wipeFitnessMetricsCacheIfNeeded(store:defaults:) is a no-op once already marked done")
    func wipeSkipsWhenAlreadyDone() async throws {
        let store = InMemoryStore()
        let defaults = Self.makeDefaults()
        defaults.set(true, forKey: TrainingAppEnvironment.fitnessMetricsCacheWipeDefaultsKey)
        try await store.upsert([FitnessMetrics.stub(day: .distantPast)])

        await TrainingAppEnvironment.wipeFitnessMetricsCacheIfNeeded(store: store, defaults: defaults)

        let remaining = try await store.cachedMetrics(in: .distantPast...Date())
        #expect(remaining.count == 1)
    }

    @Test("wipeFitnessMetricsCacheIfNeeded(store:defaults:) leaves the flag unset when the delete fails")
    func wipeLeavesFlagUnsetOnFailure() async {
        let store = FailingFitnessMetricsCacheStore()
        let defaults = Self.makeDefaults()

        await TrainingAppEnvironment.wipeFitnessMetricsCacheIfNeeded(store: store, defaults: defaults)

        #expect(!defaults.bool(forKey: TrainingAppEnvironment.fitnessMetricsCacheWipeDefaultsKey))
    }

    /// A fresh, isolated `UserDefaults` suite per test — never `.standard`, so these tests can't
    /// leak state into each other or into a real device's defaults.
    private static func makeDefaults() -> UserDefaults {
        let suiteName = "TrainingAppEnvironmentTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

/// A `FitnessMetricsCacheStore` whose `deleteCachedMetrics(from:)` always throws — used to verify
/// ``TrainingAppEnvironment/wipeFitnessMetricsCacheIfNeeded(store:defaults:)`` doesn't mark itself
/// done on a failed delete.
private struct FailingFitnessMetricsCacheStore: FitnessMetricsCacheStore {
    struct Failure: Error {}

    func cachedMetrics(in range: ClosedRange<Date>) async throws -> [FitnessMetrics] { [] }
    func cachedMetrics(immediatelyBefore date: Date) async throws -> FitnessMetrics? { nil }
    func recentLoads(before date: Date, count: Int) async throws -> [Double] { [] }
    func latestCachedDay() async throws -> Date? { nil }
    func earliestCachedDay() async throws -> Date? { nil }
    func upsert(_ metrics: [FitnessMetrics]) async throws {}
    func deleteCachedMetrics(from date: Date) async throws { throw Failure() }
    func dirtyWatermark() async throws -> Date? { nil }
    func markDirty(from date: Date) async throws {}
    func clearDirtyWatermark() async throws {}
}

private extension FitnessMetrics {
    static func stub(day: Date) -> FitnessMetrics {
        FitnessMetrics(
            day: day, load: 0, ctl: 0, atl: 0, tsb: 0, monotony: .nan, strain: .nan,
            isProjected: false, isWarmingUp: false
        )
    }
}
