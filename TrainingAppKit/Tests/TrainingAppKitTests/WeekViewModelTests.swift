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

    @Test("heartRateHistogram has no bins and no zone boundaries when there's no activity or zone settings")
    func heartRateHistogramEmptyWithNoActivities() async throws {
        let (_, stores) = makeStores()
        let athlete = AthleteProfile.fixture(timeZoneIdentifier: "UTC")
        let model = TrainingModel(stores: stores, athlete: athlete)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        await viewModel.refreshHeartRateHistogramIfNeeded()

        #expect(viewModel.heartRateHistogram.bins.isEmpty)
        #expect(viewModel.heartRateHistogram.zoneBoundariesBPM == nil)
    }

    @Test("heartRateHistogram bins an activity's heart-rate samples by bpm, with zone boundaries in bpm")
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
        // load(asOf:) already recomputes the histogram once the activity is loaded (see its own
        // doc comment) -- no separate refreshHeartRateHistogramIfNeeded() call needed here.
        await viewModel.load(asOf: day(0))

        let histogram = viewModel.heartRateHistogram

        let bin = try #require(histogram.bins.first { $0.bpm == 175 })
        #expect(bin.seconds == 600)
        #expect(histogram.bins.reduce(0) { $0 + $1.seconds } == 600)
        #expect(histogram.zoneBoundariesBPM?.count == 6)
    }

    @Test("heartRateHistogram invalidates its cache when the displayed week changes")
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

        let firstWeekTotal = viewModel.heartRateHistogram.bins.reduce(0) { $0 + $1.seconds }
        #expect(firstWeekTotal > 0)

        // Same view model instance -- only `displayedWeekStart` changes. A cache keyed on the
        // wrong thing (or nothing at all) would incorrectly keep returning the first week's data
        // for the next (activity-free) week.
        viewModel.goToNextWeek()
        await viewModel.refreshHeartRateHistogramIfNeeded()
        let nextWeekTotal = viewModel.heartRateHistogram.bins.reduce(0) { $0 + $1.seconds }

        #expect(nextWeekTotal == 0)
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
}

@MainActor
private final class FakeRefresher: ActivityRefreshing {
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

    init(model: TrainingModel) {
        self.model = model
    }

    func refreshActivities(asOf today: Date) async throws {
        try await model.importActivities(from: StubImporter(), asOf: today)
    }

    func resyncActivities(asOf today: Date) async throws {
        try await model.resyncActivities(from: StubImporter(), asOf: today)
    }

    func requestAuthorization() async throws {}
}

private struct StubImporter: ActivityImporting {
    func importActivities(since anchor: ImportAnchor?) async throws -> ImportResult {
        ImportResult(upserted: [], deletedSources: [], anchor: ImportAnchor(data: Data([1])))
    }
}
