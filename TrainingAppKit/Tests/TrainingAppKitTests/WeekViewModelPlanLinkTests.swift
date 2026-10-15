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
        planMinutes: [Double], activityMinutes: Double, startedFromPlan: Int? = nil, steps: [ActivityStep] = []
    ) async throws -> (WeekViewModel, [PlannedActivity], Activity) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
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
        let activity = Activity(
            source: .healthKit(UUID()), sport: .running, start: day(2), duration: activityMinutes * 60,
            scheduledPlanID: startedFromPlan.map { plans[$0].id }, steps: steps
        )
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
        // The linked plan's workout comes along as step cards (MVP2-144).
        #expect(!context.linkedPlanSteps.isEmpty)
    }

    @Test("a linked activity with recorded steps shows them against the plan's step, as recorded steps (MVP2-146)")
    func recordedStepsShownAgainstThePlan() async throws {
        let recorded = ActivityStep(
            block: 0, repetition: 0, step: 0, start: day(2), end: day(2).addingTimeInterval(1800),
            distanceMeters: 5000, averageHeartRateBPM: 152
        )
        let (viewModel, _, activity) = try await makeViewModel(planMinutes: [30], activityMinutes: 30, steps: [recorded])

        let context = try #require(viewModel.planLinkContext(for: activity))

        #expect(context.linkedPlanStepsAreRecorded)
        let actual = try #require(context.linkedPlanSteps.first?.steps.first?.actual)
        #expect(actual.duration == "30:00")
        #expect(actual.averageHeartRate == "152")
        #expect(actual.distance != nil && actual.averagePace != nil)
    }

    @Test("the detail view model's charts carry the linked plan's roles for the recorded steps (MVP2-146)")
    func chartsGetTheRolesOfTheLinkedPlan() async throws {
        let recorded = ActivityStep(
            block: 0, repetition: 0, step: 0, start: day(2), end: day(2).addingTimeInterval(1800)
        )
        let (viewModel, _, activity) = try await makeViewModel(planMinutes: [30], activityMinutes: 30, steps: [recorded])

        let detail = viewModel.activityDetailViewModel(for: activity)

        #expect(detail.chartData.steps.map(\.kind) == [.work])
        #expect(detail.chartData.duration == 1800)
    }

    @Test("a step card's id and its span on the charts are the same number, so a tap highlights the right band (MVP2-146)")
    func cardIDsMatchChartSpans() async throws {
        // Two planned steps recorded out of order in the activity's list.
        let workouts = StructuredWorkout(name: "Two", sport: .running, blocks: [
            WorkoutBlock(steps: [WorkoutStep(kind: .warmup, goal: .time(300))]),
            WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1500))]),
        ])
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        let model = TrainingModel(stores: stores, athlete: AthleteProfile.fixture(timeZoneIdentifier: "UTC"))
        try await model.add(workouts, asOf: day(2))
        let plan = PlannedActivity(workoutID: workouts.id, date: day(2))
        try await model.add(plan, asOf: day(2))
        try await model.load(in: day(0)...day(6), asOf: day(2))
        let warmup = ActivityStep(block: 0, repetition: 0, step: 0, start: day(2), end: day(2).addingTimeInterval(300))
        let work = ActivityStep(block: 1, repetition: 0, step: 0, start: day(2).addingTimeInterval(300), end: day(2).addingTimeInterval(1800))
        let activity = Activity(
            source: .healthKit(UUID()), sport: .running, start: day(2), duration: 1800,
            scheduledPlanID: plan.id, steps: [work, warmup]  // not in order
        )
        try await model.importActivities(from: StubImporter(activities: [activity]), asOf: day(2))
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(2))

        let detail = viewModel.activityDetailViewModel(for: model.activities[0])

        let cardIDs = try #require(detail.planLinkContext).linkedPlanSteps.flatMap(\.steps).map(\.recordedStepID)
        #expect(cardIDs == [0, 1])  // the warm-up is first in time
        #expect(detail.chartData.steps.map(\.id) == [0, 1])
        #expect(detail.chartData.steps.map(\.kind) == [.warmup, .work])
    }

    @Test("a linked activity that went on past its plan gets a card for it, numbered after the steps; without recorded steps it gets none")
    func afterPlanCardInTheContext() async throws {
        let recorded = ActivityStep(block: 0, repetition: 0, step: 0, start: day(2), end: day(2).addingTimeInterval(1200))
        // 30 minutes of activity, the plan's one step recorded for 20.
        let (viewModel, _, activity) = try await makeViewModel(planMinutes: [20], activityMinutes: 30, steps: [recorded])

        let context = try #require(viewModel.planLinkContext(for: activity))

        let after = try #require(context.linkedPlanAfter)
        #expect(after.recordedStepID == 1)
        #expect(after.actual.duration == "10:00")
        #expect(viewModel.activityDetailViewModel(for: activity).chartData.steps.last?.id == 1)

        let (plain, _, plainActivity) = try await makeViewModel(planMinutes: [20], activityMinutes: 30)
        #expect(try #require(plain.planLinkContext(for: plainActivity)).linkedPlanAfter == nil)
    }

    @Test("steps that start at the same instant are ordered by the Watch's own numbering")
    func orderedStepsTieBreak() {
        let start = day(2)
        let later = ActivityStep(block: 1, repetition: 0, step: 1, start: start, end: start.addingTimeInterval(10))
        let earlier = ActivityStep(block: 1, repetition: 0, step: 0, start: start, end: start.addingTimeInterval(10))
        let activity = Activity(source: .manual, sport: .running, start: start, duration: 60, steps: [later, earlier])

        #expect(activity.orderedSteps == [earlier, later])
    }

    @Test("a linked activity without recorded steps, or with steps that don't fit the plan, shows the plan alone")
    func plainPlanWithoutRecordedSteps() async throws {
        let (plain, _, plainActivity) = try await makeViewModel(planMinutes: [30], activityMinutes: 30)
        let plainContext = try #require(plain.planLinkContext(for: plainActivity))
        #expect(!plainContext.linkedPlanStepsAreRecorded)
        #expect(plainContext.linkedPlanSteps.first?.steps.first?.actual == nil)

        // Two recorded steps for a plan of one: the plan was edited after the workout.
        let extra = (0..<2).map {
            ActivityStep(
                block: 5 + $0, repetition: 0, step: 0, start: day(2).addingTimeInterval(Double($0) * 60),
                end: day(2).addingTimeInterval(Double($0 + 1) * 60)
            )
        }
        let (edited, _, editedActivity) = try await makeViewModel(planMinutes: [30], activityMinutes: 30, steps: extra)
        let editedContext = try #require(edited.planLinkContext(for: editedActivity))
        #expect(!editedContext.linkedPlanStepsAreRecorded)
    }

    @Test("an activity started from a scheduled plan is linked to exactly that plan, with no ambiguity (MVP2-120)")
    func linkedByScheduledPlanID() async throws {
        // 30 minutes fits plan 0 and plan 1 (31) almost equally; the Watch says it was plan 1.
        let (viewModel, plans, activity) = try await makeViewModel(
            planMinutes: [30, 31], activityMinutes: 30, startedFromPlan: 1
        )

        let context = try #require(viewModel.planLinkContext(for: activity))

        #expect(context.linkedPlan?.id == plans[1].id)
        #expect(!context.isAmbiguous)
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
                cycleStore: store, raceStore: store, athleteStore: store
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

    @Test("a linked activity's card can show what its plan expected; an unlinked one has nothing")
    func linkedPlanExpectation() async throws {
        let (viewModel, plans, activity) = try await makeViewModel(planMinutes: [30], activityMinutes: 30)
        #expect(activity.linkedPlanID == plans[0].id)

        let expectation = try #require(viewModel.linkedPlanExpectation(for: activity))
        #expect(expectation.duration == 1800)

        var unlinked = activity
        unlinked.linkedPlanID = nil
        #expect(viewModel.linkedPlanExpectation(for: unlinked) == nil)
    }

    @Test("setActivitySport changes the activity's sport and venue and keeps them (MVP2-151)")
    func setActivitySport() async throws {
        let (viewModel, _, activity) = try await makeViewModel(planMinutes: [], activityMinutes: 30)

        #expect(await viewModel.setActivitySport(activity, sport: .running, venue: .indoor(.treadmill), asOf: day(2)))

        let changed = try #require(viewModel.activities(on: day(2)).first)
        #expect(changed.venue == .indoor(.treadmill))
        #expect(changed.isSportEdited)
        #expect(viewModel.activityCardContent(for: changed).title == "Running")
    }

    @Test("a planned card summary carries its workout's venue (MVP2-151)")
    func plannedSummaryVenue() async throws {
        let (viewModel, plans, _) = try await makeViewModel(planMinutes: [30], activityMinutes: 30)
        var withVenue = workout("Treadmill", minutes: 30)
        withVenue.venue = .indoor(.treadmill)
        try await viewModel.model.add(withVenue, asOf: day(2))
        let plan = PlannedActivity(workoutID: withVenue.id, date: day(3))
        try await viewModel.model.add(plan, asOf: day(2))

        #expect(viewModel.plannedCardSummary(for: plan).venue == .indoor(.treadmill))
        #expect(viewModel.plannedCardSummary(for: plans[0]).venue == nil)
    }
}
