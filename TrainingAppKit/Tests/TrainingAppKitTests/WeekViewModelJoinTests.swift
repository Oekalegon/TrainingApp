import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@MainActor
@Suite("WeekViewModel join handling (MVP1-80)")
struct WeekViewModelJoinTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func makeViewModel(_ activities: [Activity]) async throws -> (InMemoryStore, WeekViewModel) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, athleteStore: store
        )
        try await store.upsert(activities)
        let model = TrainingModel(stores: stores, athlete: AthleteProfile.fixture(timeZoneIdentifier: "UTC"))
        try await model.load(in: day(0)...day(6), asOf: day(2))
        return (store, WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0)))
    }

    /// A 5:43 run followed, ~17 s later, by a 44:03 run — the pair this feature exists for.
    private func splitRun() -> (Activity, Activity) {
        let first = Activity(source: .healthKit(UUID()), sport: .running, start: day(2), duration: 343, distanceMeters: 668)
        let second = Activity(
            source: .healthKit(UUID()), sport: .running, start: day(2).addingTimeInterval(360),
            duration: 2643, distanceMeters: 5200
        )
        return (first, second)
    }

    @Test("A split session is warned about as a join, on both pieces, and counts toward the review total")
    func joinIsSurfacedAsWarning() async throws {
        let (a, b) = splitRun()
        let (_, viewModel) = try await makeViewModel([a, b])

        #expect(viewModel.overlapWarning(for: a) == .join)
        #expect(viewModel.overlapWarning(for: b) == .join)
        #expect(viewModel.overlapWarningCount == 2)
        let context = try #require(viewModel.overlapContext(for: a))
        #expect(context.recommendation == .join)
        #expect(context.otherActivity.id == b.id)
    }

    @Test("A join suggestion isn't hidden behind a possibleMultisport pairing that sorts earlier")
    func joinOutranksMultisport() async throws {
        let (a, b) = splitRun()
        // Contained within `a` and starting before `b`, so the checker emits (a, leg) first.
        let leg = Activity(source: .manual, sport: .cycling, start: day(2).addingTimeInterval(100), duration: 60)
        let (_, viewModel) = try await makeViewModel([a, b, leg])

        let context = try #require(viewModel.overlapContext(for: a))
        #expect(context.recommendation == .join)
        #expect(context.otherActivity.id == b.id)
        #expect(viewModel.overlapWarning(for: a) == .join)
    }

    @Test("A session split in three keeps a stable join badge on the middle piece")
    func threeWaySplitIsStable() async throws {
        let a = Activity(source: .manual, sport: .running, start: day(2), duration: 300)
        let b = Activity(source: .manual, sport: .running, start: day(2).addingTimeInterval(320), duration: 600)
        let c = Activity(source: .manual, sport: .running, start: day(2).addingTimeInterval(940), duration: 900)
        let (_, viewModel) = try await makeViewModel([a, b, c])

        #expect(viewModel.overlapWarning(for: a) == .join)
        #expect(viewModel.overlapWarning(for: b) == .join)
        #expect(viewModel.overlapWarning(for: c) == .join)
    }

    @Test("joinActivities shows one activity, lists its pieces, and clears the warning; unjoin restores them")
    func joinAndUnjoin() async throws {
        let (a, b) = splitRun()
        let (_, viewModel) = try await makeViewModel([a, b])

        await viewModel.joinActivities(a, with: b, asOf: day(2))

        let shown = viewModel.activities(on: day(2))
        #expect(shown.count == 1)
        #expect(shown.first?.distanceMeters == 5868)
        #expect(viewModel.overlapWarningCount == 0)
        let joined = try #require(shown.first)
        #expect(await viewModel.joinedComponents(of: joined).map(\.id) == [a.id, b.id])
        #expect(await viewModel.joinedComponents(of: a).isEmpty)

        await viewModel.unjoinActivity(joined, asOf: day(2))

        #expect(Set(viewModel.activities(on: day(2)).map(\.id)) == [a.id, b.id])
        #expect(viewModel.overlapWarning(for: a) == .join)
    }
}
