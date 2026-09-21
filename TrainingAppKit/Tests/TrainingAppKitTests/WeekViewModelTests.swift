import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@MainActor
@Suite("WeekViewModel")
struct WeekViewModelTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func makeStores() -> (InMemoryStore, StoreSet) {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, athleteStore: store
        )
        return (store, stores)
    }

    private func makeModel(weekStartsOn: Weekday = .monday) -> TrainingModel {
        let (_, stores) = makeStores()
        let athlete = AthleteProfile.fixture(weekStartsOn: weekStartsOn, timeZoneIdentifier: "UTC")
        return TrainingModel(stores: stores, athlete: athlete)
    }

    @Test("displayedWeekStart lands on the athlete's week-start day, not just any day")
    func displayedWeekStartRespectsWeekStartsOn() {
        let model = makeModel(weekStartsOn: .monday)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(3))

        let calendar = WeekViewModel.calendar(for: model.athlete)
        #expect(calendar.component(.weekday, from: viewModel.displayedWeekStart) == Weekday.monday.rawValue)
    }

    @Test("weekDates has exactly the 7 days starting at displayedWeekStart")
    func weekDatesIsSevenConsecutiveDays() {
        let model = makeModel()
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        #expect(viewModel.weekDates.count == 7)
        #expect(viewModel.weekDates.first == viewModel.displayedWeekStart)
    }

    @Test("weekDates(offsetWeeks:) returns the neighboring weeks without moving displayedWeekStart")
    func weekDatesWithOffsetReflectsNeighboringWeeksOnly() {
        let model = makeModel()
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        let calendar = WeekViewModel.calendar(for: model.athlete)
        let originalStart = viewModel.displayedWeekStart

        let previous = viewModel.weekDates(offsetWeeks: -1)
        let next = viewModel.weekDates(offsetWeeks: 1)

        #expect(previous.count == 7)
        #expect(next.count == 7)
        #expect(previous.first == calendar.date(byAdding: .day, value: -7, to: originalStart))
        #expect(next.first == calendar.date(byAdding: .day, value: 7, to: originalStart))
        // Neither call should have moved the actual navigation state.
        #expect(viewModel.displayedWeekStart == originalStart)
    }

    @Test("isToday(_:) matches only the calendar day of the given reference date")
    func isTodayMatchesOnlyTheReferenceDay() {
        let model = makeModel()
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        let calendar = WeekViewModel.calendar(for: model.athlete)
        let startOfDay2 = calendar.startOfDay(for: day(2))

        #expect(viewModel.isToday(day(2), asOf: day(2)))
        #expect(!viewModel.isToday(day(2), asOf: day(3)))
        #expect(!viewModel.isToday(day(2), asOf: startOfDay2.addingTimeInterval(-1)))
    }

    @Test("isPast(_:) is true only for a calendar day strictly before today's")
    func isPastMatchesOnlyDaysBeforeToday() {
        let model = makeModel()
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        #expect(viewModel.isPast(day(1), asOf: day(2)))
        #expect(!viewModel.isPast(day(2), asOf: day(2)))
        #expect(!viewModel.isPast(day(3), asOf: day(2)))
    }

    @Test("chartRange spans the week before, the displayed week, and the week after")
    func chartRangeIsThreeWeeksCenteredOnDisplayedWeek() {
        let model = makeModel()
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        let calendar = WeekViewModel.calendar(for: model.athlete)

        let expectedStart = calendar.date(byAdding: .day, value: -7, to: viewModel.displayedWeekStart)!
        let expectedEnd = calendar.date(byAdding: .day, value: 13, to: viewModel.displayedWeekStart)!

        #expect(viewModel.chartRange.lowerBound == expectedStart)
        #expect(viewModel.chartRange.upperBound == expectedEnd)
        // 3 weeks = 21 days inclusive of both ends.
        let dayCount = calendar.dateComponents([.day], from: expectedStart, to: expectedEnd).day!
        #expect(dayCount == 20)
    }

    @Test("chartRange(for:) matches chartRange for the currently displayed week, and shifts for others")
    func chartRangeForWeekStartMatchesUnparameterizedForDisplayedWeek() {
        let model = makeModel()
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        let calendar = WeekViewModel.calendar(for: model.athlete)

        #expect(viewModel.chartRange(for: viewModel.displayedWeekStart) == viewModel.chartRange)

        let nextWeekStart = calendar.date(byAdding: .day, value: 7, to: viewModel.displayedWeekStart)!
        let nextRangeStart = calendar.date(byAdding: .day, value: -7, to: nextWeekStart)!
        let nextRangeEnd = calendar.date(byAdding: .day, value: 13, to: nextWeekStart)!
        #expect(viewModel.chartRange(for: nextWeekStart) == nextRangeStart...nextRangeEnd)
    }

    @Test(
        "chartMetrics(for:) scopes to that week's own chartRange, independent of displayedWeekStart (MVP1-32)"
    )
    func chartMetricsForWeekStartIsScopedToThatWeek() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        let calendar = WeekViewModel.calendar(for: athlete)

        // Inside the *next* week's own chartRange but outside the currently displayed week's --
        // proves chartMetrics(for:) reads the given week's own window, not displayedWeekStart's.
        let nextWeekStart = calendar.date(byAdding: .day, value: 7, to: viewModel.displayedWeekStart)!
        let dayInNextWeeksRange = calendar.date(byAdding: .day, value: 18, to: viewModel.displayedWeekStart)!
        let activity = Activity(source: .manual, sport: .running, start: dayInNextWeeksRange, duration: 1800)
        try await store.upsert([activity])

        await viewModel.load(asOf: day(0))

        #expect(viewModel.chartMetrics(for: nextWeekStart).contains { calendar.isDate($0.day, inSameDayAs: dayInNextWeeksRange) })
        #expect(!viewModel.chartMetrics.contains { calendar.isDate($0.day, inSameDayAs: dayInNextWeeksRange) })
    }

    @Test("displayedWeekRange(for:) matches displayedWeekRange for the currently displayed week, and shifts for others")
    func displayedWeekRangeForWeekStartMatchesUnparameterizedForDisplayedWeek() {
        let model = makeModel()
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        let calendar = WeekViewModel.calendar(for: model.athlete)

        #expect(viewModel.displayedWeekRange(for: viewModel.displayedWeekStart) == viewModel.displayedWeekRange)

        let nextWeekStart = calendar.date(byAdding: .day, value: 7, to: viewModel.displayedWeekStart)!
        let expectedNextRange = nextWeekStart...calendar.date(byAdding: .day, value: 7, to: nextWeekStart)!
        #expect(viewModel.displayedWeekRange(for: nextWeekStart) == expectedNextRange)
    }

    @Test(
        "load(asOf:) fetches wide enough to cover the displayed week's neighbors' own chartRanges, not just its own (MVP1-32)"
    )
    func loadFetchesWideEnoughForNeighboringWeeksOwnCharts() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        let calendar = WeekViewModel.calendar(for: athlete)

        // Outside the displayed week's own chartRange (whose upper bound is +13 days) but inside
        // the *next* week's chartRange (+7 -7...+7 +13 = 0...+20) -- proves `load` reaches far
        // enough for WeekView's "next" carousel page to render its own complete chart immediately,
        // without waiting for a swipe to trigger a further load.
        let dayInNextWeeksRange = calendar.date(byAdding: .day, value: 18, to: viewModel.displayedWeekStart)!
        let activity = Activity(source: .manual, sport: .running, start: dayInNextWeeksRange, duration: 1800)
        try await store.upsert([activity])

        await viewModel.load(asOf: day(0))

        #expect(model.activities.map(\.id) == [activity.id])
    }

    @Test("displayedWeekRange tracks displayedWeekStart, following navigation rather than staying on today")
    func displayedWeekRangeFollowsNavigation() {
        let model = makeModel()
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        let calendar = WeekViewModel.calendar(for: model.athlete)

        func expectedRange(for weekStart: Date) -> ClosedRange<Date> {
            weekStart...calendar.date(byAdding: .day, value: 7, to: weekStart)!
        }

        // Before navigating, displayedWeekRange matches the initial displayed week.
        #expect(viewModel.displayedWeekRange == expectedRange(for: viewModel.displayedWeekStart))

        // After navigating, displayedWeekRange should follow displayedWeekStart, not stay behind.
        viewModel.goToNextWeek()
        viewModel.goToNextWeek()
        #expect(viewModel.displayedWeekRange == expectedRange(for: viewModel.displayedWeekStart))
    }

    @Test("displayedWeekOfYear matches the calendar's own weekOfYear component for displayedWeekStart")
    func displayedWeekOfYearMatchesCalendarComponent() {
        let model = makeModel()
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        let calendar = WeekViewModel.calendar(for: model.athlete)

        #expect(viewModel.displayedWeekOfYear == calendar.component(.weekOfYear, from: viewModel.displayedWeekStart))

        viewModel.goToNextWeek()
        #expect(viewModel.displayedWeekOfYear == calendar.component(.weekOfYear, from: viewModel.displayedWeekStart))
    }

    @Test("displayedWeekDateRangeDescription spans displayedWeekStart through 6 days later, with the year on the end date")
    func displayedWeekDateRangeDescriptionSpansTheWeek() {
        let model = makeModel()
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        let calendar = WeekViewModel.calendar(for: model.athlete)
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: viewModel.displayedWeekStart)!

        let description = viewModel.displayedWeekDateRangeDescription

        #expect(description.contains(String(calendar.component(.year, from: weekEnd))))
        #expect(!description.isEmpty)
    }

    /// Dec 26, 2022 (Mon) – Jan 1, 2023 (Sun): only 1 of its 7 days falls in 2023, so ISO-8601
    /// calls this week 52 of 2022, not week 1 of 2023 — Foundation's own Gregorian default
    /// (`minimumDaysInFirstWeek == 1`) would say week 1 of 2023, which is what an athlete's other
    /// tools (and their own expectation) would disagree with.
    private func dateOfDecember28th2022() -> Date {
        var components = DateComponents()
        components.year = 2022
        components.month = 12
        components.day = 28
        components.timeZone = TimeZone(identifier: "UTC")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)!
    }

    @Test("displayedWeekOfYear follows ISO-8601 week numbering across a year boundary, not Foundation's Gregorian default")
    func displayedWeekOfYearFollowsISO8601NearYearBoundary() {
        let model = makeModel()
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: dateOfDecember28th2022())

        // The literal expected ISO week number, not the same Calendar computation under test —
        // this is the case that catches a wrong `minimumDaysInFirstWeek`, which a test that only
        // re-derives the expectation from `WeekViewModel.calendar(for:)` itself cannot.
        #expect(viewModel.displayedWeekOfYear == 52)
    }

    @Test("displayedWeekDateRangeDescription shows both years when the week crosses a year boundary")
    func displayedWeekDateRangeDescriptionShowsBothYearsAcrossBoundary() {
        let model = makeModel()
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: dateOfDecember28th2022())

        let description = viewModel.displayedWeekDateRangeDescription

        #expect(description.contains("2022"))
        #expect(description.contains("2023"))
    }

    @Test("goToNextWeek/goToPreviousWeek move by exactly 7 days")
    func weekNavigationMovesBySevenDays() {
        let model = makeModel()
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        let start = viewModel.displayedWeekStart
        let calendar = WeekViewModel.calendar(for: model.athlete)

        viewModel.goToNextWeek()
        #expect(viewModel.displayedWeekStart == calendar.date(byAdding: .day, value: 7, to: start))

        viewModel.goToPreviousWeek()
        viewModel.goToPreviousWeek()
        #expect(viewModel.displayedWeekStart == calendar.date(byAdding: .day, value: -7, to: start))
    }

    @Test("goToToday returns to the week containing the given date after navigating away")
    func goToTodayReturnsToCurrentWeek() {
        let model = makeModel()
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        let start = viewModel.displayedWeekStart

        viewModel.goToNextWeek()
        viewModel.goToNextWeek()
        #expect(viewModel.displayedWeekStart != start)

        viewModel.goToToday(asOf: day(0))
        #expect(viewModel.displayedWeekStart == start)
    }

    @Test("goToWeek(containing:) jumps to an arbitrary date's week, not just today's")
    func goToWeekJumpsToArbitraryDate() {
        let model = makeModel()
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        let calendar = WeekViewModel.calendar(for: model.athlete)
        // Several weeks away from `today`, so this can't be confused with `goToToday`'s target.
        let target = day(40)
        let expectedStart = calendar.dateInterval(of: .weekOfYear, for: target)!.start

        viewModel.goToWeek(containing: target)

        #expect(viewModel.displayedWeekStart == expectedStart)
        #expect(viewModel.displayedWeekStart != calendar.dateInterval(of: .weekOfYear, for: day(0))!.start)
    }

    @Test("activities(on:) and plans(on:) filter to exactly that calendar day")
    func activitiesAndPlansFilterByDay() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let workout = StructuredWorkout(
            name: "Steady", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800), target: .heartRateZone(2))])]
        )
        let onDay = Activity(source: .manual, sport: .running, start: day(2), duration: 1800)
        let otherDay = Activity(source: .manual, sport: .cycling, start: day(3), duration: 1800)
        let plan = PlannedActivity(workoutID: workout.id, date: day(2))
        try await store.upsert([workout])
        try await store.upsert([onDay, otherDay])
        try await store.upsert([plan])

        let model = TrainingModel(stores: stores, athlete: athlete)
        try await model.load(in: day(0)...day(6), asOf: day(2))
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        #expect(viewModel.activities(on: day(2)).map(\.id) == [onDay.id])
        #expect(viewModel.activities(on: day(3)).map(\.id) == [otherDay.id])
        #expect(viewModel.plans(on: day(2)).map(\.id) == [plan.id])
        #expect(viewModel.plans(on: day(3)).isEmpty)
        #expect(viewModel.workout(for: plan)?.id == workout.id)
    }

    @Test("plannedCardSummary shows distance for a distance-only workout, duration otherwise, and falls back when the workout is missing")
    func plannedCardSummaryExtent() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let timed = StructuredWorkout(
            name: "Steady", sport: .cycling,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800), target: .heartRateZone(2))])]
        )
        let distance = StructuredWorkout(
            name: "Reps", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .distance(400), target: .heartRateZone(4))], repetitions: 5)]
        )
        let timedPlan = PlannedActivity(workoutID: timed.id, date: day(2))
        let distancePlan = PlannedActivity(workoutID: distance.id, date: day(2), expectedLoadOverride: 55)
        let orphanPlan = PlannedActivity(workoutID: UUID(), date: day(2))
        try await store.upsert([timed, distance])
        try await store.upsert([timedPlan, distancePlan, orphanPlan])

        let model = TrainingModel(stores: stores, athlete: athlete)
        try await model.load(in: day(0)...day(6), asOf: day(2))
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        let timedSummary = viewModel.plannedCardSummary(for: timedPlan)
        #expect(timedSummary.sport == .cycling)
        #expect(timedSummary.name == "Steady")
        #expect(timedSummary.extent == .duration(1800))

        let distanceSummary = viewModel.plannedCardSummary(for: distancePlan)
        #expect(distanceSummary.extent == .distance(meters: 2000))
        #expect(distanceSummary.load == 55)

        let orphanSummary = viewModel.plannedCardSummary(for: orphanPlan)
        #expect(orphanSummary.sport == .running)
        #expect(orphanSummary.name == nil)
        #expect(orphanSummary.extent == nil)
    }

    @Test("plannedCardSummary shows duration for mixed/open workouts and for a workout with no steps, never 0 m")
    func plannedCardSummaryMixedOpenAndEmpty() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let mixed = StructuredWorkout(
            name: "Mixed", sport: .running,
            blocks: [WorkoutBlock(steps: [
                WorkoutStep(kind: .work, goal: .distance(1000), target: .heartRateZone(3)),
                WorkoutStep(kind: .work, goal: .time(600), target: .heartRateZone(2)),
            ])]
        )
        let open = StructuredWorkout(
            name: "Open", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .open, target: .heartRateZone(2))])]
        )
        let empty = StructuredWorkout(name: "Empty", sport: .running, blocks: [WorkoutBlock(steps: [])])
        let plans = [mixed, open, empty].map { PlannedActivity(workoutID: $0.id, date: day(2)) }
        try await store.upsert([mixed, open, empty])
        try await store.upsert(plans)

        let model = TrainingModel(stores: stores, athlete: athlete)
        try await model.load(in: day(0)...day(6), asOf: day(2))
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        for plan in plans {
            guard case .duration = viewModel.plannedCardSummary(for: plan).extent else {
                Issue.record("expected a duration extent for \(String(describing: viewModel.workout(for: plan)?.name))")
                continue
            }
        }
    }

    @Test("pendingPlans(on:) omits plans already matched to a completed activity")
    func pendingPlansOmitsReconciled() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let workout = StructuredWorkout(
            name: "Steady", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800), target: .heartRateZone(2))])]
        )
        let pending = PlannedActivity(workoutID: workout.id, date: day(2))
        let matched = PlannedActivity(workoutID: workout.id, date: day(2), completedActivityID: UUID())
        try await store.upsert([workout])
        try await store.upsert([pending, matched])

        let model = TrainingModel(stores: stores, athlete: athlete)
        try await model.load(in: day(0)...day(6), asOf: day(2))
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        #expect(viewModel.pendingPlans(on: day(2)).map(\.id) == [pending.id])
        #expect(viewModel.plans(on: day(2)).count == 2)
    }

    @Test("metrics(on:) returns the matching day's fitness metrics, nil outside the loaded range")
    func metricsOnDayFiltersToThatCalendarDay() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let activity = Activity(source: .manual, sport: .running, start: day(2), duration: 1800)
        try await store.upsert([activity])

        let model = TrainingModel(stores: stores, athlete: athlete)
        try await model.load(in: day(0)...day(6), asOf: day(2))
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        let calendar = WeekViewModel.calendar(for: athlete)
        let metricsOnDay2 = try #require(viewModel.metrics(on: day(2)))
        #expect(calendar.isDate(metricsOnDay2.day, inSameDayAs: day(2)))
        #expect(viewModel.metrics(on: day(100)) == nil)
    }

    @Test("trainingLoad(for:) computes a value when a calculator can score the activity, nil otherwise")
    func trainingLoadReflectsWhetherACalculatorSucceeds() throws {
        let model = makeModel()
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        // No heart-rate samples and no perceivedExertion: neither calculator can score it.
        let unscored = Activity(source: .manual, sport: .running, start: day(2), duration: 1800)
        #expect(viewModel.trainingLoad(for: unscored) == nil)

        // perceivedExertion alone is enough for DurationRPECalculator to succeed.
        let scored = Activity(
            source: .manual, sport: .running, start: day(2), duration: 1800, perceivedExertion: 6
        )
        let loaded = try #require(viewModel.trainingLoad(for: scored))
        #expect(loaded == 180.0)
    }

    @Test(
        "overlapWarning(for:) surfaces a real overlap issue, but not a possibleMultisport pairing (MVP1-63)"
    )
    func overlapWarningSkipsPossibleMultisportButSurfacesRealIssues() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")

        // Same time span, same sport, differing data (only `a` has heart-rate samples) -> .merge.
        let a = Activity(
            source: .manual, sport: .running, start: day(2), duration: 1800,
            heartRate: [HeartRateSample(time: day(2), bpm: 140)]
        )
        let b = Activity(source: .manual, sport: .running, start: day(2), duration: 1800)
        // Fully contained within `a`, different sport -> .possibleMultisport, not a warning.
        let leg = Activity(source: .manual, sport: .cycling, start: day(2).addingTimeInterval(60), duration: 60)
        // No overlap with anything.
        let unrelated = Activity(source: .manual, sport: .swimming, start: day(4), duration: 1800)
        try await store.upsert([a, b, leg, unrelated])

        let model = TrainingModel(stores: stores, athlete: athlete)
        try await model.load(in: day(0)...day(6), asOf: day(2))
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        #expect(viewModel.overlapWarning(for: a) == .merge)
        #expect(viewModel.overlapWarning(for: b) == .merge)
        #expect(viewModel.overlapWarning(for: leg) == nil)
        #expect(viewModel.overlapWarning(for: unrelated) == nil)
    }

    @Test(
        "overlapContext(for:) names the specific other activity, including a possibleMultisport pairing (MVP1-63)"
    )
    func overlapContextNamesTheOtherActivity() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")

        let a = Activity(
            source: .manual, sport: .running, start: day(2), duration: 1800,
            heartRate: [HeartRateSample(time: day(2), bpm: 140)]
        )
        let b = Activity(source: .manual, sport: .running, start: day(2), duration: 1800)
        let contained = Activity(source: .manual, sport: .swimming, start: day(3), duration: 3600)
        let leg = Activity(source: .manual, sport: .cycling, start: day(3).addingTimeInterval(60), duration: 60)
        try await store.upsert([a, b, contained, leg])

        let model = TrainingModel(stores: stores, athlete: athlete)
        try await model.load(in: day(0)...day(6), asOf: day(2))
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        let mergeContext = try #require(viewModel.overlapContext(for: a))
        #expect(mergeContext.recommendation == .merge)
        #expect(mergeContext.otherActivity.id == b.id)

        // Unlike overlapWarning(for:), this surfaces possibleMultisport too (MVP1-29: the detail
        // sheet is where all four recommendation types should appear distinctly).
        let multisportContext = try #require(viewModel.overlapContext(for: leg))
        #expect(multisportContext.recommendation == .possibleMultisport)
        #expect(multisportContext.otherActivity.id == contained.id)

        let unrelated = Activity(source: .manual, sport: .rowing, start: day(5), duration: 1800)
        try await store.upsert([unrelated])
        try await model.load(in: day(0)...day(6), asOf: day(2))
        #expect(viewModel.overlapContext(for: unrelated) == nil)
    }

    @Test("overlapReviewItems lists every non-multisport-flagged activity once, sorted by start (MVP1-63)")
    func overlapReviewItemsListsAndSorts() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")

        // A slight start offset (still within sameSessionTolerance) so `a`/`b` sort deterministically.
        let a = Activity(
            source: .manual, sport: .running, start: day(3), duration: 1800,
            heartRate: [HeartRateSample(time: day(3), bpm: 140)]
        )
        let b = Activity(
            source: .manual, sport: .running, start: day(3).addingTimeInterval(10), duration: 1800
        )
        // A possibleMultisport pairing -- excluded from the review list.
        let contained = Activity(source: .manual, sport: .swimming, start: day(2), duration: 3600)
        let leg = Activity(source: .manual, sport: .cycling, start: day(2).addingTimeInterval(60), duration: 60)
        try await store.upsert([a, b, contained, leg])

        let model = TrainingModel(stores: stores, athlete: athlete)
        try await model.load(in: day(0)...day(6), asOf: day(2))
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        #expect(viewModel.overlapReviewItems.map(\.activity.id) == [a.id, b.id])
        #expect(viewModel.overlapReviewItems.map(\.recommendation) == [.merge, .merge])
    }

    @Test("resolveOverlap(deleting:) removes the activity from the store and from activities(on:) (MVP1-63)")
    func resolveOverlapDeletesActivity() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let a = Activity(source: .manual, sport: .running, start: day(2), duration: 1800)
        let b = Activity(source: .manual, sport: .running, start: day(2), duration: 1800)
        try await store.upsert([a, b])

        let model = TrainingModel(stores: stores, athlete: athlete)
        try await model.load(in: day(0)...day(6), asOf: day(2))
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        #expect(viewModel.activities(on: day(2)).count == 2)

        await viewModel.resolveOverlap(deleting: b.id, asOf: day(2))

        #expect(viewModel.activities(on: day(2)).map(\.id) == [a.id])
        #expect(try await store.activity(id: b.id) == nil)
    }

    @Test("deleteActivity(_:asOf:) removes an activity unconditionally, not just an overlap side (MVP1-65)")
    func deleteActivityRemovesAnyActivity() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        // No overlap involved at all -- proves this isn't limited to resolveOverlap's use case.
        let solo = Activity(source: .manual, sport: .running, start: day(2), duration: 1800)
        try await store.upsert([solo])

        let model = TrainingModel(stores: stores, athlete: athlete)
        try await model.load(in: day(0)...day(6), asOf: day(2))
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        #expect(viewModel.activities(on: day(2)).map(\.id) == [solo.id])

        await viewModel.deleteActivity(solo, asOf: day(2))

        #expect(viewModel.activities(on: day(2)).isEmpty)
        #expect(try await store.activity(id: solo.id) == nil)
    }

    @Test("overlapWarningCount is live: reflects model.overlapAdvice right away, and updates once an overlap is resolved (MVP1-67)")
    func overlapWarningCountIsLive() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let a = Activity(source: .manual, sport: .running, start: day(2), duration: 1800)
        let b = Activity(source: .manual, sport: .running, start: day(2), duration: 1800)
        // A possibleMultisport pairing -- doesn't count toward the total.
        let contained = Activity(source: .manual, sport: .swimming, start: day(3), duration: 3600)
        let leg = Activity(source: .manual, sport: .cycling, start: day(3).addingTimeInterval(60), duration: 60)
        try await store.upsert([a, b, contained, leg])

        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        await viewModel.load(asOf: day(0))

        // No separate "import finished" step needed -- unlike the old `overlapImportSummary`
        // snapshot, the count reflects `model.overlapAdvice` the moment the data is loaded.
        #expect(viewModel.overlapWarningCount == 2)

        // ...and stays live across an unrelated refresh (proving it isn't a one-time snapshot
        // `refresh(asOf:)` alone populates).
        await viewModel.refresh(asOf: day(0))
        #expect(viewModel.overlapWarningCount == 2)

        // Resolving one side of the overlap updates the live count immediately, with no separate
        // refresh step -- the bug MVP1-67 fixes: the old `overlapImportSummary` snapshot stayed
        // frozen at 2 here even after this delete.
        await viewModel.resolveOverlap(deleting: a.id, asOf: day(0))
        #expect(viewModel.overlapWarningCount == 0)
    }

    @Test("connectHealthData(asOf:) and resyncActivities(asOf:) also surface a live overlapWarningCount (MVP1-67)")
    func connectHealthDataAndResyncSurfaceLiveOverlapWarningCount() async throws {
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let a = Activity(source: .manual, sport: .running, start: day(2), duration: 1800)
        let b = Activity(source: .manual, sport: .running, start: day(2), duration: 1800)
        let importer = OverlapProducingImporter(activities: [a, b])

        let (_, connectStores) = makeStores()
        let connectModel = TrainingModel(stores: connectStores, athlete: athlete)
        let connectRefresher = ModelBackedFakeRefresher(model: connectModel, importer: importer)
        let connectViewModel = WeekViewModel(model: connectModel, refresher: connectRefresher, today: day(0))
        await connectViewModel.load(asOf: day(0))
        #expect(connectViewModel.overlapWarningCount == 0)
        await connectViewModel.connectHealthData(asOf: day(0))
        #expect(connectViewModel.overlapWarningCount == 2)

        let (_, resyncStores) = makeStores()
        let resyncModel = TrainingModel(stores: resyncStores, athlete: athlete)
        let resyncRefresher = ModelBackedFakeRefresher(model: resyncModel, importer: importer)
        let resyncViewModel = WeekViewModel(model: resyncModel, refresher: resyncRefresher, today: day(0))
        await resyncViewModel.load(asOf: day(0))
        #expect(resyncViewModel.overlapWarningCount == 0)
        await resyncViewModel.resyncActivities(asOf: day(0))
        #expect(resyncViewModel.overlapWarningCount == 2)
    }

    @Test("sportStatsPages(asOf:) has exactly one, zero-filled page for the main sport when nothing was tracked")
    func sportStatsPagesZeroFillsWhenNoActivity() async {
        let model = makeModel()
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        await viewModel.load(asOf: day(0))

        let pages = viewModel.sportStatsPages(asOf: day(0))

        #expect(pages.map(\.sport) == [model.athlete.mainSport])
        let page = pages[0]
        #expect(page.distanceMeters == 0)
        #expect(page.time == 0)
        #expect(page.load == 0)
        // Neither week had any activity -- genuinely "no change", not an infinite one.
        #expect(page.distanceChangeFraction == 0)
        #expect(page.timeChangeFraction == 0)
        #expect(page.loadChangeFraction == 0)
    }

    @Test("sportStatsPages(asOf:) computes this week's totals and their percentage change vs. last week")
    func sportStatsPagesComputesPercentageChange() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        let calendar = WeekViewModel.calendar(for: athlete)
        let previousWeekDay = calendar.date(byAdding: .day, value: -7, to: viewModel.displayedWeekStart)!

        // 10000m/2000s last week, 15000m/3000s this week -- both +50%.
        let previousActivity = Activity(
            source: .manual, sport: athlete.mainSport, start: previousWeekDay,
            duration: 2000, distanceMeters: 10000
        )
        let currentActivity = Activity(
            source: .manual, sport: athlete.mainSport, start: viewModel.displayedWeekStart,
            duration: 3000, distanceMeters: 15000
        )
        try await store.upsert([previousActivity, currentActivity])
        await viewModel.load(asOf: day(0))

        let page = try #require(viewModel.sportStatsPages(asOf: day(0)).first)

        #expect(page.distanceMeters == 15000)
        #expect(page.time == 3000)
        #expect(abs(page.distanceChangeFraction - 0.5) < 0.0001)
        #expect(abs(page.timeChangeFraction - 0.5) < 0.0001)
    }

    @Test("sportStatsPages(asOf:) reports an infinite change from a zero previous-week baseline")
    func sportStatsPagesReportsInfiniteChangeFromZeroBaseline() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        // No activity last week at all, some this week -- an unbounded increase, not "+0%".
        let currentActivity = Activity(
            source: .manual, sport: athlete.mainSport, start: viewModel.displayedWeekStart,
            duration: 1800, distanceMeters: 5000
        )
        try await store.upsert([currentActivity])
        await viewModel.load(asOf: day(0))

        let page = try #require(viewModel.sportStatsPages(asOf: day(0)).first)

        #expect(page.distanceChangeFraction == .infinity)
        #expect(page.timeChangeFraction == .infinity)
        // Load stays 0 for both weeks here (no heart-rate/RPE data for either activity) -- a
        // genuine 0-over-0, not an infinite change.
        #expect(page.loadChangeFraction == 0)
    }

    @Test("sportStatsPages(asOf:) puts the main sport first, then other tracked sports by distance descending")
    func sportStatsPagesOrdersMainSportFirstThenByDistance() async throws {
        let (store, stores) = makeStores()
        // Default AthleteProfile.fixture() has .running as mainSport.
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        let running = Activity(
            source: .manual, sport: .running, start: viewModel.displayedWeekStart,
            duration: 1800, distanceMeters: 5000
        )
        let cycling = Activity(
            source: .manual, sport: .cycling, start: viewModel.displayedWeekStart,
            duration: 3600, distanceMeters: 30000
        )
        let swimming = Activity(
            source: .manual, sport: .swimming, start: viewModel.displayedWeekStart,
            duration: 1200, distanceMeters: 1000
        )
        try await store.upsert([running, cycling, swimming])
        await viewModel.load(asOf: day(0))

        let pages = viewModel.sportStatsPages(asOf: day(0))

        // Running is the main sport, so it leads even though cycling covered more distance;
        // cycling then swimming follow, ordered by distance descending.
        #expect(pages.map(\.sport) == [.running, .cycling, .swimming])
    }

    @Test("sportStatsPages(asOf:) reports the whole week's total load, unchanged across every page")
    func sportStatsPagesLoadIsWholeWeekTotalOnEveryPage() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        // Both scored via perceivedExertion, so each contributes real (non-zero) load.
        let running = Activity(
            source: .manual, sport: .running, start: viewModel.displayedWeekStart,
            duration: 1800, perceivedExertion: 5
        )
        let cycling = Activity(
            source: .manual, sport: .cycling, start: viewModel.displayedWeekStart,
            duration: 3600, perceivedExertion: 7
        )
        try await store.upsert([running, cycling])
        await viewModel.load(asOf: day(0))

        let pages = viewModel.sportStatsPages(asOf: day(0))

        #expect(pages.map(\.sport) == [.running, .cycling])
        let totalLoad = pages[0].load
        #expect(totalLoad > 0)
        // Load isn't sliced per sport here -- both pages report the same whole-week total.
        #expect(pages.allSatisfy { $0.load == totalLoad })
    }

    @Test("sportStatsPages(asOf:) reports performed and planned distance/time/load independently, not blended (MVP2-31)")
    func sportStatsPagesReportsPerformedAndPlannedIndependently() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC", restingHeartRateBPM: 50, maxHeartRateBPM: 190)
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        // `today` is `displayedWeekStart` itself (not `day(0)`), so "planned dated the day after"
        // is unambiguously both >= today and still inside the displayed week, regardless of which
        // weekday the `day(0)` epoch fixture happens to land on.
        let today = viewModel.displayedWeekStart
        let performed = Activity(
            source: .manual, sport: .running, start: today,
            duration: 1800, distanceMeters: 5000, perceivedExertion: 5
        )
        let workout = StructuredWorkout(
            name: "Easy Run", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800), target: .heartRateZone(2))])]
        )
        // A day after `today` that has no completed activity of its own -- unlike `periodStats`'s
        // merged figure, this plan must still show up under
        // `plannedDistanceMeters`/`plannedTime`/`plannedLoad` even though the week already has a
        // completed activity on a different day.
        let plannedDate = today.addingTimeInterval(86400)
        let plan = PlannedActivity(workoutID: workout.id, date: plannedDate)
        try await store.upsert([performed])
        try await store.upsert([workout])
        try await store.upsert([plan])
        await viewModel.load(asOf: today)

        let pages = viewModel.sportStatsPages(asOf: today)
        let runningPage = try #require(pages.first { $0.sport == .running })

        #expect(runningPage.distanceMeters == 5000)
        #expect(runningPage.time == 1800)
        #expect(runningPage.load > 0)
        #expect(runningPage.plannedDistanceMeters > 0)
        #expect(runningPage.plannedTime > 0)
        #expect(runningPage.plannedLoad > 0)
        // Neither side's totals absorb the other's -- the plan's own duration (1800s) stays
        // distinct from the performed activity's (also 1800s but a real, separately-measured
        // figure), rather than one clobbering or summing into the other.
        #expect(runningPage.plannedTime == 1800)
        #expect(runningPage.time == 1800)
    }

    @Test("sportStatsPages(asOf:) computes expected*ChangeFraction against the previous week's performed total, not the plan alone (MVP2-31)")
    func sportStatsPagesExpectedChangeFractionComparesAgainstPreviousPerformed() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC", restingHeartRateBPM: 50, maxHeartRateBPM: 190)
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        let calendar = WeekViewModel.calendar(for: athlete)

        let today = viewModel.displayedWeekStart
        let previousWeekDay = calendar.date(byAdding: .day, value: -7, to: today)!
        let previousWeekActivity = Activity(
            source: .manual, sport: .running, start: previousWeekDay, duration: 1500, distanceMeters: 4000, perceivedExertion: 5
        )
        let thisWeekActivity = Activity(
            source: .manual, sport: .running, start: today, duration: 1800, distanceMeters: 5000, perceivedExertion: 5
        )
        let workout = StructuredWorkout(
            name: "Easy Run", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .distance(5000), target: .heartRateZone(2))])]
        )
        let plan = PlannedActivity(workoutID: workout.id, date: today.addingTimeInterval(86400))
        try await store.upsert([previousWeekActivity, thisWeekActivity])
        try await store.upsert([workout])
        try await store.upsert([plan])
        await viewModel.load(asOf: today)

        let pages = viewModel.sportStatsPages(asOf: today)
        let runningPage = try #require(pages.first { $0.sport == .running })

        // Expected distance = 5000 (performed) + the plan's own projected distance, compared
        // against last week's 4000 performed -- a strictly larger relative increase than
        // performed-alone's own change fraction, since the plan adds on top of it.
        #expect(runningPage.distanceChangeFraction == (5000.0 - 4000.0) / 4000.0)
        #expect(runningPage.expectedDistanceChangeFraction > runningPage.distanceChangeFraction)
    }

    @Test("sportStatsPages(for:asOf:) compares a fully future week against the previous week's own expected (not performed-only) total (MVP2-31)")
    func sportStatsPagesFutureWeekComparesAgainstPreviousExpected() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC", restingHeartRateBPM: 50, maxHeartRateBPM: 190)
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        let calendar = WeekViewModel.calendar(for: athlete)

        let today = viewModel.displayedWeekStart
        let nextWeekStart = calendar.date(byAdding: .day, value: 7, to: today)!
        let twoWeeksOutStart = calendar.date(byAdding: .day, value: 14, to: today)!

        let workout = StructuredWorkout(
            name: "Easy Run", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .distance(5000), target: .heartRateZone(2))])]
        )
        // Nothing performed at all -- `today`'s own week needs its own real plan too, so nextWeek
        // has a genuine (non-zero) baseline to compare against; without one, `today`'s week's own
        // expected total would itself be 0, and this test would just be exercising the same "+∞%"
        // bug from a different angle instead of proving the fix.
        let plans = [
            PlannedActivity(workoutID: workout.id, date: today),
            PlannedActivity(workoutID: workout.id, date: nextWeekStart),
            PlannedActivity(workoutID: workout.id, date: twoWeeksOutStart),
        ]
        try await store.upsert([workout])
        try await store.upsert(plans)
        await viewModel.load(asOf: today)

        // Before this fix, nextWeek's change fraction compared against `today`'s own week's
        // performed-only total (0, since nothing's been performed yet) and twoWeeksOut's compared
        // against nextWeek's performed-only total (also 0) -- both read as a meaningless "+∞%".
        let nextWeekPage = try #require(viewModel.sportStatsPages(for: nextWeekStart, asOf: today).first { $0.sport == .running })
        #expect(nextWeekPage.expectedDistanceChangeFraction.isFinite)

        let twoWeeksOutPage = try #require(viewModel.sportStatsPages(for: twoWeeksOutStart, asOf: today).first { $0.sport == .running })
        #expect(twoWeeksOutPage.expectedDistanceChangeFraction.isFinite)
        // twoWeeksOut's own plan (5000m) is identical to nextWeek's own plan (5000m) -- comparing
        // against nextWeek's planned total (the correct baseline, since nextWeek's performed total
        // is itself 0) should read as "no change", not the same "+∞%" a performed-only baseline
        // would still report.
        #expect(twoWeeksOutPage.expectedDistanceChangeFraction == 0)
    }

    @Test("sportStatsPages(asOf:) scopes the 80/20 intensity split to each page's own sport, not blended across sports")
    func sportStatsPagesPolarizedSplitIsScopedPerSport() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(
            timeZoneIdentifier: "UTC", restingHeartRateBPM: 50, maxHeartRateBPM: 190
        )
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        let weekStart = viewModel.displayedWeekStart
        // 175bpm (well above threshold with a 50/190 resting/max split) lands in a
        // moderate-to-high zone; 100bpm lands low -- same fixture pattern
        // `heartRateHistogramBinsActivitySamples` uses. Running gets only the hard samples,
        // cycling only the easy ones -- if the split were still blended across sports (as it
        // briefly was), each page would incorrectly report the same 50/50 mix instead of its own
        // sport's 100% moderate-to-high / 100% low.
        let hardSamples = stride(from: 0, through: 600, by: 30).map {
            HeartRateSample(time: weekStart.addingTimeInterval(TimeInterval($0)), bpm: 175)
        }
        let easySamples = stride(from: 0, through: 600, by: 30).map {
            HeartRateSample(time: weekStart.addingTimeInterval(3600 + TimeInterval($0)), bpm: 100)
        }
        let running = Activity(source: .manual, sport: .running, start: weekStart, duration: 600, heartRate: hardSamples)
        let cycling = Activity(
            source: .manual, sport: .cycling, start: weekStart.addingTimeInterval(3600), duration: 600,
            heartRate: easySamples
        )
        try await store.upsert([running, cycling])
        await viewModel.load(asOf: day(0))

        let pages = viewModel.sportStatsPages(asOf: day(0))

        #expect(pages.map(\.sport) == [.running, .cycling])
        let runningSplit = pages[0].polarizedSplit
        #expect(runningSplit.total == 600)
        #expect(runningSplit.lowSeconds == 0)
        #expect(runningSplit.moderateToHighSeconds == 600)
        let cyclingSplit = pages[1].polarizedSplit
        #expect(cyclingSplit.total == 600)
        #expect(cyclingSplit.lowSeconds == 600)
        #expect(cyclingSplit.moderateToHighSeconds == 0)
    }

    @Test("sportStatsPages(asOf:) reports a planned workout's projected intensity under plannedPolarizedSplit, not polarizedSplit (MVP2-31)")
    func sportStatsPagesPolarizedSplitIncludesPlannedWorkoutProjection() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(
            timeZoneIdentifier: "UTC", restingHeartRateBPM: 50, maxHeartRateBPM: 190
        )
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        let calendar = WeekViewModel.calendar(for: athlete)

        // Entirely in the future -- no completed activities at all, so `polarizedSplit` (performed)
        // stays empty and the projection can only show up under `plannedPolarizedSplit`.
        let nextWeekStart = calendar.date(byAdding: .day, value: 7, to: viewModel.displayedWeekStart)!
        // `.heartRateZone(2)` lands in zone 2 with a 50/190 resting/max split (midpoint ratio 0.65
        // falls inside the karvonen zone-2 range), which `polarizedSplit` counts as "low" -- same
        // zone-mapping precedent `activitiesAndPlansFilterByDay` uses for its own workout fixture.
        let workout = StructuredWorkout(
            name: "Easy Run", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800), target: .heartRateZone(2))])]
        )
        let plan = PlannedActivity(workoutID: workout.id, date: nextWeekStart)
        try await store.upsert([workout])
        try await store.upsert([plan])
        await viewModel.load(asOf: day(0))

        let pages = viewModel.sportStatsPages(for: nextWeekStart, asOf: day(0))

        #expect(pages[0].polarizedSplit.total == 0)
        let plannedSplit = pages[0].plannedPolarizedSplit
        #expect(plannedSplit.total == 1800)
        #expect(plannedSplit.lowSeconds == 1800)
        #expect(plannedSplit.moderateToHighSeconds == 0)
    }

    @Test("sportStatsPages(asOf:) invalidates its cache when the displayed week changes")
    func sportStatsPagesRecomputesAfterWeekNavigation() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        let thisWeekActivity = Activity(
            source: .manual, sport: athlete.mainSport, start: viewModel.displayedWeekStart,
            duration: 1800, distanceMeters: 5000
        )
        try await store.upsert([thisWeekActivity])
        await viewModel.load(asOf: day(0))

        let firstWeekPages = viewModel.sportStatsPages(asOf: day(0))
        #expect(firstWeekPages[0].distanceMeters == 5000)

        // Same view model instance, same `today` -- only `displayedWeekStart` changes. A cache
        // keyed on the wrong thing (e.g. just `today`, or nothing at all) would incorrectly keep
        // returning the first week's 5000m here instead of the next (empty) week's 0m.
        viewModel.goToNextWeek()
        let nextWeekPages = viewModel.sportStatsPages(asOf: day(0))

        #expect(nextWeekPages[0].distanceMeters == 0)
    }

    @Test("heartRateHistogram(for:) has no bins and no zone boundaries when there's no activity or zone settings")
    func heartRateHistogramEmptyWithNoActivities() async throws {
        let (_, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        await viewModel.refreshWeekCachesIfNeeded()

        let histogram = viewModel.heartRateHistogram(for: viewModel.displayedWeekStart)
        #expect(histogram.bins.isEmpty)
        #expect(histogram.zoneBoundariesBPM == nil)
    }

    @Test("heartRateHistogram(for:) bins an activity's heart-rate samples by bpm, with zone boundaries in bpm")
    func heartRateHistogramBinsActivitySamples() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(
            timeZoneIdentifier: "UTC", restingHeartRateBPM: 50, maxHeartRateBPM: 190
        )
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        let activityDay = viewModel.displayedWeekStart
        // 30s apart (well under the 60s gap threshold), so the whole 10 minutes forms one
        // continuous segment instead of being excluded as a pause -- same fixture pattern
        // `ActivityDetailViewModelTests` uses for a heart-rate-scored activity. A constant 175bpm
        // keeps every segment's average bpm in the same 5-wide bin, so the total lands in one bin.
        let samples = stride(from: 0, through: 600, by: 30).map {
            HeartRateSample(time: activityDay.addingTimeInterval(TimeInterval($0)), bpm: 175)
        }
        let activity = Activity(
            source: .manual, sport: .running, start: activityDay, duration: 600, heartRate: samples
        )
        try await store.upsert([activity])
        // load(asOf:) already recomputes the caches once the activity is loaded (see its own
        // doc comment) -- no separate refreshWeekCachesIfNeeded() call needed here.
        await viewModel.load(asOf: day(0))

        let histogram = viewModel.heartRateHistogram(for: viewModel.displayedWeekStart)

        let bin = try #require(histogram.bins.first { $0.bpm == 175 })
        #expect(bin.seconds == 600)
        #expect(histogram.bins.reduce(0) { $0 + $1.seconds } == 600)
        #expect(histogram.zoneBoundariesBPM?.count == 6)
    }

    @Test("heartRateHistogram(for:) invalidates its cache when the displayed week changes")
    func heartRateHistogramRecomputesAfterWeekNavigation() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(
            timeZoneIdentifier: "UTC", restingHeartRateBPM: 50, maxHeartRateBPM: 190
        )
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        let activityDay = viewModel.displayedWeekStart
        let samples = stride(from: 0, through: 600, by: 30).map {
            HeartRateSample(time: activityDay.addingTimeInterval(TimeInterval($0)), bpm: 175)
        }
        let activity = Activity(
            source: .manual, sport: .running, start: activityDay, duration: 600, heartRate: samples
        )
        try await store.upsert([activity])
        await viewModel.load(asOf: day(0))

        let firstWeekTotal = viewModel.heartRateHistogram(for: viewModel.displayedWeekStart)
            .bins.reduce(0) { $0 + $1.seconds }
        #expect(firstWeekTotal > 0)

        // Same view model instance -- only `displayedWeekStart` changes. Each week is keyed by its
        // own `weekStart`, so looking up the (activity-free) next week should never return the
        // first week's cached data.
        viewModel.goToNextWeek()
        await viewModel.refreshWeekCachesIfNeeded()
        let nextWeekTotal = viewModel.heartRateHistogram(for: viewModel.displayedWeekStart)
            .bins.reduce(0) { $0 + $1.seconds }

        #expect(nextWeekTotal == 0)
    }

    @Test("heartRateHistogram(for:) recomputes for the same displayed week once activity count changes")
    func heartRateHistogramRecomputesAfterActivityCountChanges() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(
            timeZoneIdentifier: "UTC", restingHeartRateBPM: 50, maxHeartRateBPM: 190
        )
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        let weekStart = viewModel.displayedWeekStart
        let firstActivity = Activity(
            source: .manual, sport: .running, start: weekStart, duration: 600,
            heartRate: stride(from: 0, through: 600, by: 30).map {
                HeartRateSample(time: weekStart.addingTimeInterval(TimeInterval($0)), bpm: 175)
            }
        )
        try await store.upsert([firstActivity])
        await viewModel.load(asOf: day(0))

        let firstTotal = viewModel.heartRateHistogram(for: weekStart).bins.reduce(0) { $0 + $1.seconds }
        #expect(firstTotal == 600)

        // Same displayed week, no navigation -- only `model.activities.count` changes (as it would
        // after a pull-to-refresh import). `refreshWeekCachesIfNeeded()`'s own fix (not clearing
        // the cache synchronously, to avoid a spurious empty-state flash) must still land the
        // freshly recomputed total here rather than getting stuck on the now-stale first value.
        let secondActivity = Activity(
            source: .manual, sport: .running, start: weekStart.addingTimeInterval(3600), duration: 600,
            heartRate: stride(from: 0, through: 600, by: 30).map {
                HeartRateSample(time: weekStart.addingTimeInterval(3600 + TimeInterval($0)), bpm: 140)
            }
        )
        try await store.upsert([secondActivity])
        await viewModel.load(asOf: day(0))

        let secondTotal = viewModel.heartRateHistogram(for: weekStart).bins.reduce(0) { $0 + $1.seconds }
        #expect(secondTotal == 1200)
    }

    @Test("heartRateHistogram(for:) prefetches the displayed week's immediate neighbors")
    func heartRateHistogramPrefetchesNeighboringWeeks() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(
            timeZoneIdentifier: "UTC", restingHeartRateBPM: 50, maxHeartRateBPM: 190
        )
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        let activityDay = viewModel.displayedWeekStart
        let nextWeekDay = viewModel.athleteCalendar.date(byAdding: .day, value: 7, to: activityDay)!
        let samples = stride(from: 0, through: 600, by: 30).map {
            HeartRateSample(time: activityDay.addingTimeInterval(TimeInterval($0)), bpm: 175)
        }
        let nextWeekSamples = stride(from: 0, through: 600, by: 30).map {
            HeartRateSample(time: nextWeekDay.addingTimeInterval(TimeInterval($0)), bpm: 140)
        }
        let currentWeekActivity = Activity(
            source: .manual, sport: .running, start: activityDay, duration: 600, heartRate: samples
        )
        let nextWeekActivity = Activity(
            source: .manual, sport: .running, start: nextWeekDay, duration: 600, heartRate: nextWeekSamples
        )
        try await store.upsert([currentWeekActivity, nextWeekActivity])
        await viewModel.load(asOf: day(0))

        // Still on the first week, but the next week's own histogram should already be cached --
        // a real navigation to it shouldn't need a fresh async computation.
        let nextWeekStart = viewModel.athleteCalendar.date(byAdding: .day, value: 7, to: viewModel.displayedWeekStart)!
        let prefetched = viewModel.heartRateHistogram(for: nextWeekStart)

        #expect(prefetched.bins.reduce(0) { $0 + $1.seconds } > 0)
    }

    @Test("activityDetailViewModel(for:) wires the model's athlete through")
    func activityDetailViewModelUsesModelAthlete() {
        let (_, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "Europe/Amsterdam")
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        let activity = Activity(source: .manual, sport: .running, start: day(0), duration: 1800)

        let detail = viewModel.activityDetailViewModel(for: activity)

        #expect(detail.activity.id == activity.id)
        #expect(detail.timeZone.identifier == "Europe/Amsterdam")
    }

    @Test("athleteViewModel wires the model's athlete through")
    func athleteViewModelUsesModelAthlete() {
        let (_, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "Europe/Amsterdam")
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        #expect(viewModel.athleteViewModel.athlete.timeZone.identifier == "Europe/Amsterdam")
    }

    @Test("metrics(in:asOf:) returns metrics restricted to the requested range, even far outside the default window")
    func metricsInRangeFiltersToThatRange() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        let calendar = WeekViewModel.calendar(for: athlete)

        let farPastDay = calendar.date(byAdding: .day, value: -200, to: viewModel.displayedWeekStart)!
        // `perceivedExertion` so `DailyLoadSeries` can actually score this activity -- an
        // unscorable one (no heart rate, no RPE) contributes no day to the series at all, which
        // would make this test pass or fail for the wrong reason entirely.
        let activity = Activity(
            source: .manual, sport: .running, start: farPastDay, duration: 1800, perceivedExertion: 5
        )
        try await store.upsert([activity])

        let rangeStart = calendar.date(byAdding: .day, value: -210, to: viewModel.displayedWeekStart)!
        let metrics = await viewModel.metrics(in: rangeStart...viewModel.displayedWeekStart, asOf: day(0))

        #expect(metrics.contains { calendar.isDate($0.day, inSameDayAs: farPastDay) })
    }

    @Test("metrics(in:asOf:) doesn't drop data the currently displayed week still needs")
    func metricsInRangeDoesNotClobberCurrentWeek() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        let calendar = WeekViewModel.calendar(for: athlete)

        let currentWeekActivity = Activity(
            source: .manual, sport: .running, start: viewModel.displayedWeekStart, duration: 1800
        )
        try await store.upsert([currentWeekActivity])
        await viewModel.load(asOf: day(0))
        #expect(viewModel.activities(on: viewModel.displayedWeekStart).map(\.id) == [currentWeekActivity.id])

        // A far-past, unrelated range -- TrainingModel.load(in:) replaces activities/plans/metrics
        // outright, so this must be unioned with the already-loaded window rather than requested
        // on its own, or the current week's own activity would disappear from the model.
        let farPastStart = calendar.date(byAdding: .day, value: -400, to: viewModel.displayedWeekStart)!
        let farPastEnd = calendar.date(byAdding: .day, value: -370, to: viewModel.displayedWeekStart)!
        _ = await viewModel.metrics(in: farPastStart...farPastEnd, asOf: day(0))

        #expect(viewModel.activities(on: viewModel.displayedWeekStart).map(\.id) == [currentWeekActivity.id])
    }

    @Test("dailyLoadSplit(in:asOf:) returns the actual/planned split restricted to the requested range, even far outside the default window (MVP2-31)")
    func dailyLoadSplitInRangeFiltersToThatRange() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        let calendar = WeekViewModel.calendar(for: athlete)

        let farPastDay = calendar.date(byAdding: .day, value: -200, to: viewModel.displayedWeekStart)!
        let activity = Activity(
            source: .manual, sport: .running, start: farPastDay, duration: 1800, perceivedExertion: 5
        )
        try await store.upsert([activity])

        let rangeStart = calendar.date(byAdding: .day, value: -210, to: viewModel.displayedWeekStart)!
        let split = await viewModel.dailyLoadSplit(in: rangeStart...viewModel.displayedWeekStart, asOf: day(0))

        #expect(split.actual.contains { calendar.isDate($0.day, inSameDayAs: farPastDay) })
    }

    @Test("dailyLoadSplit(in:asOf:) doesn't drop data the currently displayed week still needs (MVP2-31)")
    func dailyLoadSplitInRangeDoesNotClobberCurrentWeek() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        let calendar = WeekViewModel.calendar(for: athlete)

        let currentWeekActivity = Activity(
            source: .manual, sport: .running, start: viewModel.displayedWeekStart, duration: 1800, perceivedExertion: 5
        )
        try await store.upsert([currentWeekActivity])
        await viewModel.load(asOf: day(0))
        #expect(viewModel.activities(on: viewModel.displayedWeekStart).map(\.id) == [currentWeekActivity.id])

        let farPastStart = calendar.date(byAdding: .day, value: -400, to: viewModel.displayedWeekStart)!
        let farPastEnd = calendar.date(byAdding: .day, value: -370, to: viewModel.displayedWeekStart)!
        _ = await viewModel.dailyLoadSplit(in: farPastStart...farPastEnd, asOf: day(0))

        #expect(viewModel.activities(on: viewModel.displayedWeekStart).map(\.id) == [currentWeekActivity.id])
    }

    @Test("load(asOf:) loads chartRange (3 weeks), not just the displayed week")
    func loadFetchesChartRangeIntoModel() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        // Inside chartRange (the week after the displayed one) but outside weekDates — proves
        // `load` fetches the wider 3-week window, not just the 7 displayed days.
        let calendar = WeekViewModel.calendar(for: athlete)
        let nextWeekDay = calendar.date(byAdding: .day, value: 10, to: viewModel.displayedWeekStart)!
        let activity = Activity(source: .manual, sport: .running, start: nextWeekDay, duration: 1800)
        try await store.upsert([activity])
        #expect(model.activities.isEmpty)

        await viewModel.load(asOf: day(0))

        #expect(model.activities.map(\.id) == [activity.id])
    }

    @Test("hasNoActivities reflects whether an import has ever happened, for the empty-state prompt")
    func hasNoActivitiesReflectsModelState() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        #expect(viewModel.hasNoActivities)

        try await store.saveImportAnchor(ImportAnchor(data: Data([1])))
        try await model.load(in: day(0)...day(6), asOf: day(0))

        #expect(!viewModel.hasNoActivities)
    }

    @Test("hasNoActivities stays false once imported, even if the current chart range has no activities")
    func hasNoActivitiesIgnoresCurrentlyLoadedRange() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        // An activity months outside the loaded chart range -- proves hasNoActivities doesn't
        // flip back on just because the displayed week's window happens to be empty.
        let outOfRange = Activity(source: .healthKit(UUID()), sport: .running, start: day(200), duration: 1800)
        try await store.upsert([outOfRange])
        try await store.saveImportAnchor(ImportAnchor(data: Data([1])))

        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        await viewModel.load(asOf: day(0))

        #expect(model.activities.isEmpty)
        #expect(!viewModel.hasNoActivities)
    }

    @Test("refresh(asOf:) toggles isRefreshing and delegates to the refresher")
    func refreshDelegatesAndTogglesFlag() async {
        let model = makeModel()
        let refresher = FakeRefresher()
        let viewModel = WeekViewModel(model: model, refresher: refresher, today: day(0))

        #expect(!viewModel.isRefreshing)
        await viewModel.refresh(asOf: day(0))
        #expect(!viewModel.isRefreshing)
        #expect(refresher.callCount == 1)
    }

    @Test("refresh(asOf:) clears isRefreshing even when the refresher throws")
    func refreshClearsFlagOnFailure() async {
        let model = makeModel()
        let refresher = FakeRefresher(shouldThrow: true)
        let viewModel = WeekViewModel(model: model, refresher: refresher, today: day(0))

        await viewModel.refresh(asOf: day(0))
        #expect(!viewModel.isRefreshing)
    }

    @Test("resyncActivities(asOf:) toggles isResyncing and delegates to the refresher")
    func resyncDelegatesAndTogglesFlag() async {
        let model = makeModel()
        let refresher = FakeRefresher()
        let viewModel = WeekViewModel(model: model, refresher: refresher, today: day(0))

        #expect(!viewModel.isResyncing)
        await viewModel.resyncActivities(asOf: day(0))
        #expect(!viewModel.isResyncing)
        #expect(refresher.resyncCallCount == 1)
    }

    @Test("resyncActivities(asOf:) clears isResyncing even when the refresher throws")
    func resyncClearsFlagOnFailure() async {
        let model = makeModel()
        let refresher = FakeRefresher(shouldThrow: true)
        let viewModel = WeekViewModel(model: model, refresher: refresher, today: day(0))

        await viewModel.resyncActivities(asOf: day(0))
        #expect(!viewModel.isResyncing)
    }

    @Test("resyncActivities(asOf:) doesn't affect isRefreshing, and vice versa")
    func resyncAndRefreshFlagsAreIndependent() async {
        let model = makeModel()
        let refresher = FakeRefresher()
        let viewModel = WeekViewModel(model: model, refresher: refresher, today: day(0))

        await viewModel.resyncActivities(asOf: day(0))
        #expect(!viewModel.isRefreshing)

        await viewModel.refresh(asOf: day(0))
        #expect(!viewModel.isResyncing)
    }

    @Test("deduplicateActivities(asOf:) toggles isDeduplicating, independent of isRefreshing/isResyncing")
    func deduplicateTogglesFlagIndependently() async {
        let model = makeModel()
        let refresher = FakeRefresher()
        let viewModel = WeekViewModel(model: model, refresher: refresher, today: day(0))

        #expect(!viewModel.isDeduplicating)
        await viewModel.deduplicateActivities(asOf: day(0))
        #expect(!viewModel.isDeduplicating)
        #expect(!viewModel.isRefreshing)
        #expect(!viewModel.isResyncing)
    }

    @Test("deduplicateActivities(asOf:) reaches TrainingModel end-to-end")
    func deduplicateActivitiesUpdatesModelEndToEnd() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture()
        let activity = Activity(source: .healthKit(UUID()), sport: .running, start: day(0), duration: 1800)
        try await store.upsert([activity])

        let model = TrainingModel(stores: stores, athlete: athlete)
        try await model.load(in: day(0)...day(0), asOf: day(0))
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        // InMemoryStore's own upsert already prevents real duplicates from existing (see
        // TrainingKit's own InMemoryStoreTests/SwiftDataStoreTests for that store-level
        // behavior), so this can't assert a removal here -- what it proves is that the call
        // genuinely reaches the real TrainingModel/store round trip (not a stub) and leaves a
        // legitimate, non-duplicate activity untouched, without crashing.
        await viewModel.deduplicateActivities(asOf: day(0))

        #expect(model.activities.map(\.id) == [activity.id])
    }

    @Test("resyncActivities(asOf:) reaches TrainingModel end-to-end, same as refresh(asOf:) does")
    func resyncActivitiesUpdatesModelEndToEnd() async throws {
        let model = makeModel()
        let refresher = ModelBackedFakeRefresher(model: model)
        let viewModel = WeekViewModel(model: model, refresher: refresher, today: day(0))
        #expect(viewModel.hasNoActivities)

        await viewModel.resyncActivities(asOf: day(0))

        #expect(!viewModel.hasNoActivities)
    }

    @Test("connectHealthData(asOf:) requests authorization before refreshing")
    func connectHealthDataRequestsAuthorizationThenRefreshes() async {
        let model = makeModel()
        let refresher = FakeRefresher()
        let viewModel = WeekViewModel(model: model, refresher: refresher, today: day(0))

        await viewModel.connectHealthData(asOf: day(0))

        #expect(refresher.authorizationRequested)
        #expect(refresher.callCount == 1)
        #expect(!viewModel.isRefreshing)
    }

    @Test("connectHealthData(asOf:) skips the import if authorization fails")
    func connectHealthDataSkipsRefreshOnAuthorizationFailure() async {
        let model = makeModel()
        let refresher = FakeRefresher(shouldThrow: true)
        let viewModel = WeekViewModel(model: model, refresher: refresher, today: day(0))

        await viewModel.connectHealthData(asOf: day(0))

        #expect(refresher.authorizationRequested)
        #expect(refresher.callCount == 0)
        #expect(!viewModel.isRefreshing)
    }

    @Test("connectHealthData(asOf:) clears hasNoActivities once the import completes")
    func connectHealthDataClearsEmptyState() async throws {
        let model = makeModel()
        let refresher = ModelBackedFakeRefresher(model: model)
        let viewModel = WeekViewModel(model: model, refresher: refresher, today: day(0))
        #expect(viewModel.hasNoActivities)

        await viewModel.connectHealthData(asOf: day(0))

        #expect(!viewModel.hasNoActivities)
    }

    @Test("dailyLoadSplit(for:) reports only a planned bar for a planned-but-not-yet-performed day (MVP2-30)")
    func dailyLoadSplitPlannedOnlyWhenNotYetPerformed() async throws {
        let (store, stores) = makeStores()
        // Zone settings needed for `TRIMPPlanEstimator` to project a non-zero load for the
        // `.heartRateZone(2)` workout below -- same fixture precedent
        // `sportStatsPagesPolarizedSplitIncludesPlannedWorkoutProjection` uses.
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC", restingHeartRateBPM: 50, maxHeartRateBPM: 190)
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        let workout = StructuredWorkout(
            name: "Easy Run", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800), target: .heartRateZone(2))])]
        )
        let plan = PlannedActivity(workoutID: workout.id, date: day(0))
        try await store.upsert([workout])
        try await store.upsert([plan])
        await viewModel.load(asOf: day(0))

        let split = viewModel.dailyLoadSplit(for: viewModel.displayedWeekStart, asOf: day(0))

        #expect(split.planned.contains { $0.load > 0 })
        #expect(split.actual.isEmpty)
    }

    @Test("dailyLoadSplit(for:) reports both bars, independently, once a planned day is also performed (MVP2-30)")
    func dailyLoadSplitReportsBothOnceAlsoPerformed() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC", restingHeartRateBPM: 50, maxHeartRateBPM: 190)
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        let workout = StructuredWorkout(
            name: "Easy Run", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800), target: .heartRateZone(2))])]
        )
        let plan = PlannedActivity(workoutID: workout.id, date: day(0))
        // A bit more load than the plan's own estimate -- the concrete "performed more than
        // predicted" case from the MVP2-30 report this split exists to show correctly.
        let activity = Activity(
            source: .manual, sport: .running, start: day(0), duration: 2400, perceivedExertion: 5
        )
        try await store.upsert([workout])
        try await store.upsert([plan])
        try await store.upsert([activity])
        await viewModel.load(asOf: day(0))

        let split = viewModel.dailyLoadSplit(for: viewModel.displayedWeekStart, asOf: day(0))

        #expect(split.planned.contains { $0.load > 0 })
        #expect(split.actual.contains { $0.load > 0 })
        // Both computed independently -- unlike `FitnessMetrics.load`'s either/or merge rule,
        // the plan's own original estimate must still be there, not replaced by the actual figure.
        let plannedDay = split.planned.first { calendar(for: athlete).isDate($0.day, inSameDayAs: day(0)) }
        let actualDay = split.actual.first { calendar(for: athlete).isDate($0.day, inSameDayAs: day(0)) }
        #expect(plannedDay?.load != actualDay?.load)
    }

    @Test("dailyLoadSplit(for:) reports only an actual bar for a completed activity with no matching plan (MVP2-30)")
    func dailyLoadSplitActualOnlyWithNoPlan() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        let activity = Activity(
            source: .manual, sport: .running, start: day(0), duration: 1800, perceivedExertion: 4
        )
        try await store.upsert([activity])
        await viewModel.load(asOf: day(0))

        let split = viewModel.dailyLoadSplit(for: viewModel.displayedWeekStart, asOf: day(0))

        #expect(split.actual.contains { $0.load > 0 })
        #expect(split.planned.isEmpty)
    }

    @Test("dailyLoadSplit(for:asOf:) doesn't show a planned bar for a day before today that was never performed (MVP2-30)")
    func dailyLoadSplitExcludesPastNeverPerformedPlans() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC", restingHeartRateBPM: 50, maxHeartRateBPM: 190)
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(5))

        let workout = StructuredWorkout(
            name: "Easy Run", sport: .running,
            blocks: [WorkoutBlock(steps: [WorkoutStep(kind: .work, goal: .time(1800), target: .heartRateZone(2))])]
        )
        // Dated before `today` and never performed -- unlike a still-upcoming plan, this should
        // read as genuinely missed, not as a bar the chart keeps showing indefinitely (matching
        // DailyLoadSeries/StatisticsCalculator.periodStats's own today-or-later merge rule for a
        // plan's contribution).
        let pastPlan = PlannedActivity(workoutID: workout.id, date: day(2))
        try await store.upsert([workout])
        try await store.upsert([pastPlan])
        await viewModel.load(asOf: day(5))

        let split = viewModel.dailyLoadSplit(for: viewModel.displayedWeekStart, asOf: day(5))

        #expect(split.planned.isEmpty)
    }

    @Test("dailyLoadSplit(for:asOf:) reuses its cached result until the underlying data actually changes (MVP2-30)")
    func dailyLoadSplitCachesUntilDataChanges() async throws {
        let (store, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        await viewModel.load(asOf: day(0))

        let first = viewModel.dailyLoadSplit(for: viewModel.displayedWeekStart, asOf: day(0))
        #expect(first.actual.isEmpty)

        // Added directly through the store, bypassing `viewModel`/`model` entirely -- a stale
        // cache that only invalidates on navigation (rather than on the activity/plan/workout
        // counts this cache is actually keyed on) would still report the old, empty split here.
        let activity = Activity(
            source: .manual, sport: .running, start: day(0), duration: 1800, perceivedExertion: 4
        )
        try await store.upsert([activity])
        await viewModel.load(asOf: day(0))

        let second = viewModel.dailyLoadSplit(for: viewModel.displayedWeekStart, asOf: day(0))
        #expect(second.actual.contains { $0.load > 0 })
    }

    private func calendar(for athlete: AthleteProfile) -> Calendar {
        WeekViewModel.calendar(for: athlete)
    }
}

@MainActor
final class FakeRefresher: ActivityRefreshing {
    private(set) var callCount = 0
    private(set) var authorizationRequested = false
    private let shouldThrow: Bool

    init(shouldThrow: Bool = false) {
        self.shouldThrow = shouldThrow
    }

    struct Boom: Error {}

    private(set) var resyncCallCount = 0

    func refreshActivities(asOf today: Date) async throws {
        callCount += 1
        if shouldThrow { throw Boom() }
    }

    func resyncActivities(asOf today: Date) async throws {
        resyncCallCount += 1
        if shouldThrow { throw Boom() }
    }

    func requestAuthorization() async throws {
        authorizationRequested = true
        if shouldThrow { throw Boom() }
    }
}

/// Unlike `FakeRefresher`, which just counts calls, this actually drives `model.importActivities(from:)`
/// with a stub `ActivityImporting` — so a test can assert the real end-to-end effect of a refresh/
/// connect on `model` (and therefore on anything, like `WeekViewModel.hasNoActivities`, that's
/// derived from it), the way the app's real `TrainingAppEnvironment` does.
@MainActor
private final class ModelBackedFakeRefresher: ActivityRefreshing {
    private let model: TrainingModel
    private let importer: any ActivityImporting

    init(model: TrainingModel, importer: any ActivityImporting = StubImporter()) {
        self.model = model
        self.importer = importer
    }

    func refreshActivities(asOf today: Date) async throws {
        try await model.importActivities(from: importer, asOf: today)
    }

    func resyncActivities(asOf today: Date) async throws {
        try await model.resyncActivities(from: importer, asOf: today)
    }

    func requestAuthorization() async throws {}
}

private struct StubImporter: ActivityImporting {
    func importActivities(since anchor: ImportAnchor?) async throws -> ImportResult {
        ImportResult(upserted: [], deletedSources: [], anchor: ImportAnchor(data: Data([1])))
    }
}

/// Unlike `StubImporter`, actually hands back `activities` as freshly "imported" -- lets a test
/// assert `WeekViewModel.overlapWarningCount` (MVP1-67) is live through `connectHealthData(asOf:)`/
/// `resyncActivities(asOf:)` specifically, not just `refresh(asOf:)`.
private struct OverlapProducingImporter: ActivityImporting {
    let activities: [Activity]

    func importActivities(since anchor: ImportAnchor?) async throws -> ImportResult {
        ImportResult(upserted: activities, deletedSources: [], anchor: ImportAnchor(data: Data([1])))
    }
}
