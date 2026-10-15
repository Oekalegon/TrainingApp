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
            cycleStore: store, raceStore: store, athleteStore: store
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

    @Test("An activity's review-list label matches its card badge when it's named by several pairs")
    func reviewLabelMatchesBadge() async throws {
        // `a` and `b` share a span (differing data -> .merge); `c` starts 10 s after `a` ends, so
        // `a` is also named by a .join pair. Merge outranks join for both surfaces.
        let a = Activity(
            source: .manual, sport: .running, start: day(2), duration: 1800,
            heartRate: [HeartRateSample(time: day(2), bpm: 140)]
        )
        let b = Activity(source: .manual, sport: .running, start: day(2), duration: 1800)
        let c = Activity(source: .manual, sport: .running, start: day(2).addingTimeInterval(1810), duration: 600)
        let (_, viewModel) = try await makeViewModel([a, b, c])

        #expect(viewModel.overlapWarning(for: a) == .merge)
        let row = try #require(viewModel.overlapReviewItems.first { $0.activity.id == a.id })
        #expect(row.recommendation == .merge)
        // Every review row agrees with its own badge, and each activity appears once.
        for item in viewModel.overlapReviewItems {
            #expect(viewModel.overlapWarning(for: item.activity) == item.recommendation)
        }
        #expect(Set(viewModel.overlapReviewItems.map(\.activity.id)).count == viewModel.overlapReviewItems.count)
    }

    @Test("A refused join reports false and leaves the activities as they were")
    func refusedJoinReportsFalse() async throws {
        let run = Activity(source: .manual, sport: .running, start: day(2), duration: 600)
        let ride = Activity(source: .manual, sport: .cycling, start: day(2).addingTimeInterval(620), duration: 600)
        let (_, viewModel) = try await makeViewModel([run, ride])

        let joined = await viewModel.joinActivities(run, with: ride, asOf: day(2))

        #expect(joined == false)
        #expect(Set(viewModel.activities(on: day(2)).map(\.id)) == [run.id, ride.id])
    }

    @Test("A successful join and unjoin report true, and unjoining an ordinary activity is a harmless no-op")
    func successReportsTrue() async throws {
        let (a, b) = splitRun()
        let (_, viewModel) = try await makeViewModel([a, b])

        #expect(await viewModel.joinActivities(a, with: b, asOf: day(2)) == true)
        let joined = try #require(viewModel.activities(on: day(2)).first)
        #expect(await viewModel.unjoinActivity(joined, asOf: day(2)) == true)
        #expect(await viewModel.unjoinActivity(a, asOf: day(2)) == true)
        #expect(Set(viewModel.activities(on: day(2)).map(\.id)) == [a.id, b.id])
    }

    @Test("A joined activity is scored once: its load is the whole session's, not a piece's")
    func joinedLoadIsWholeSession() async throws {
        let a = Activity(source: .manual, sport: .running, start: day(2), duration: 600, perceivedExertion: 5)
        let b = Activity(source: .manual, sport: .running, start: day(2).addingTimeInterval(620), duration: 1200, perceivedExertion: 5)
        let (_, viewModel) = try await makeViewModel([a, b])

        await viewModel.joinActivities(a, with: b, asOf: day(2))

        let shown = viewModel.activities(on: day(2))
        #expect(shown.count == 1)
        // duration spans 0...1820 s -> 30.33 min at RPE 5.
        let joined = try #require(shown.first)
        let load = try #require(viewModel.trainingLoad(for: joined))
        #expect(abs(load - (1820.0 / 60.0) * 5) < 0.01)
    }
}
