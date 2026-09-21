import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@MainActor
@Suite("WeekViewModel plan linking (MVP2-42)")
struct WeekViewModelPlanLinkTests {
    private struct StubImporter: ActivityImporting {
        let activities: [Activity]
        func importActivities(since anchor: ImportAnchor?) async throws -> ImportResult {
            ImportResult(upserted: activities, deletedSources: [], anchor: nil)
        }
    }

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func workout(_ name: String, minutes: Double) -> StructuredWorkout {
        StructuredWorkout(
            name: name, sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(minutes * 60))])]
        )
    }

    /// A model with one workout/plan per entry of `minutes` on day 2, and the activity imported
    /// (so it's auto-matched, as in the app).
    private func makeViewModel(
        planMinutes: [Double], activityMinutes: Double
    ) async throws -> (WeekViewModel, [PlannedActivity], Activity) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, athleteStore: store
        )
        let model = TrainingModel(stores: stores, athlete: AthleteProfile.fixture(timeZoneIdentifier: "UTC"))
        var plans: [PlannedActivity] = []
        for (index, minutes) in planMinutes.enumerated() {
            let w = workout("Run \(index)", minutes: minutes)
            try await model.add(w, asOf: day(2))
            let plan = PlannedActivity(workoutID: w.id, date: day(2))
            try await model.add(plan, asOf: day(2))
            plans.append(plan)
        }
        try await model.load(in: day(0)...day(6), asOf: day(2))
        let activity = Activity(source: .healthKit(UUID()), sport: .running, start: day(2), duration: activityMinutes * 60)
        try await model.importActivities(from: StubImporter(activities: [activity]), asOf: day(2))
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(2))
        return (viewModel, plans, model.activities[0])
    }

    @Test("a clearly matched activity shows its plan, with no ambiguity and no alternatives")
    func linkedContext() async throws {
        let (viewModel, plans, activity) = try await makeViewModel(planMinutes: [30], activityMinutes: 30)

        let context = try #require(viewModel.planLinkContext(for: activity))

        #expect(context.linkedPlan?.id == plans[0].id)
        #expect(context.linkedPlan?.title == "Run 0")
        #expect(!context.isAmbiguous)
        #expect(context.candidates.isEmpty)
    }

    @Test("a near-tie is flagged as ambiguous and offers the other plan")
    func ambiguousContext() async throws {
        let (viewModel, plans, activity) = try await makeViewModel(planMinutes: [30, 31], activityMinutes: 30)

        let context = try #require(viewModel.planLinkContext(for: activity))

        #expect(context.isAmbiguous)
        #expect(context.candidates.map(\.id) == [plans[1].id])
    }

    @Test("with no plan on the day there's nothing to show")
    func noContext() async throws {
        let (viewModel, _, activity) = try await makeViewModel(planMinutes: [], activityMinutes: 30)

        #expect(viewModel.planLinkContext(for: activity) == nil)
    }

    @Test("linking switches the plan and the detail view model carries the context")
    func linkAndConfirm() async throws {
        let (viewModel, plans, activity) = try await makeViewModel(planMinutes: [30, 31], activityMinutes: 30)
        let other = try #require(viewModel.planLinkContext(for: activity)?.candidates.first)

        #expect(await viewModel.linkActivity(activity, toPlan: other.id, asOf: day(2)))

        let relinked = try #require(viewModel.model.activities.first)
        let context = try #require(viewModel.planLinkContext(for: relinked))
        #expect(context.linkedPlan?.id == other.id)
        #expect(!context.isAmbiguous)
        #expect(context.candidates.map(\.id) == [plans[0].id])
        #expect(viewModel.activityDetailViewModel(for: relinked).planLinkContext == context)
    }

    @Test("unlinking removes the link and offers the plan again")
    func unlink() async throws {
        let (viewModel, plans, activity) = try await makeViewModel(planMinutes: [30], activityMinutes: 30)

        #expect(await viewModel.unlinkActivity(activity, asOf: day(2)))

        let unlinked = try #require(viewModel.model.activities.first)
        let context = try #require(viewModel.planLinkContext(for: unlinked))
        #expect(context.linkedPlan == nil)
        #expect(context.candidates.map(\.id) == [plans[0].id])
    }

    @Test("a plan on another day can't be linked")
    func differentDayRefused() async throws {
        let (viewModel, _, activity) = try await makeViewModel(planMinutes: [], activityMinutes: 30)
        let w = workout("Later", minutes: 30)
        try await viewModel.model.add(w, asOf: day(2))
        let later = PlannedActivity(workoutID: w.id, date: day(3))
        try await viewModel.model.add(later, asOf: day(2))

        #expect(await viewModel.linkActivity(activity, toPlan: later.id, asOf: day(2)) == false)
        #expect(viewModel.model.activities.first?.linkedPlanID == nil)
    }

    @Test("confirming the current match clears the ambiguity and keeps the link")
    func confirmClearsAmbiguity() async throws {
        let (viewModel, _, activity) = try await makeViewModel(planMinutes: [30, 31], activityMinutes: 30)
        let context = try #require(viewModel.planLinkContext(for: activity))
        let current = try #require(context.linkedPlan)
        #expect(context.isAmbiguous)

        #expect(await viewModel.linkActivity(activity, toPlan: current.id, asOf: day(2)))

        let confirmed = try #require(viewModel.model.activities.first)
        let after = try #require(viewModel.planLinkContext(for: confirmed))
        #expect(after.linkedPlan?.id == current.id)
        #expect(!after.isAmbiguous)
    }

    @Test("\"same day\" follows the athlete's time zone, not UTC")
    func candidatesUseAthleteTimeZone() async throws {
        let auckland = try #require(TimeZone(identifier: "Pacific/Auckland"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = auckland
        func local(day: Int, hour: Int, minute: Int = 0) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: day, hour: hour, minute: minute)))
        }
        let store = InMemoryStore()
        let model = TrainingModel(
            stores: StoreSet(
                activityStore: store, planStore: store, workoutStore: store,
                cycleStore: store, athleteStore: store
            ),
            athlete: AthleteProfile.fixture(timeZoneIdentifier: "Pacific/Auckland")
        )
        let w = workout("Run", minutes: 30)
        try await model.add(w, asOf: try local(day: 10, hour: 12))
        // Same Auckland day as the activity below (though not the same UTC day) and the next one.
        let sameDay = PlannedActivity(workoutID: w.id, date: try local(day: 10, hour: 7))
        let nextDay = PlannedActivity(workoutID: w.id, date: try local(day: 11, hour: 7))
        try await model.add(sameDay, asOf: try local(day: 10, hour: 12))
        try await model.add(nextDay, asOf: try local(day: 10, hour: 12))
        let activity = Activity(
            source: .manual, sport: .running, start: try local(day: 10, hour: 23, minute: 30), duration: 1800
        )
        try await store.upsert([activity])
        try await model.load(in: try local(day: 9, hour: 0)...(try local(day: 12, hour: 0)), asOf: try local(day: 10, hour: 12))
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: try local(day: 10, hour: 12))

        let context = try #require(viewModel.planLinkContext(for: activity))

        #expect(context.candidates.map(\.id) == [sameDay.id])
    }
}
