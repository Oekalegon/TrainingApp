import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@MainActor
@Suite("DisplayPeriod")
struct DisplayPeriodTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func makeModel(timeZone: String = "UTC") -> TrainingModel {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        let athlete = AthleteProfile.fixture(weekStartsOn: .monday, timeZoneIdentifier: timeZone)
        return TrainingModel(stores: stores, athlete: athlete)
    }

    /// A view model on a plan of five micro-cycles of `length` days, the middle one containing `day(0)`.
    private func uniformViewModel(_ model: TrainingModel, length: Int) async throws -> WeekViewModel {
        let calendar = calendar(model)
        let start = WeekViewModel.weekStart(containing: day(0), calendar: calendar)
        try await seedPlan(model, lengths: Array(repeating: length, count: 5), anchoredAt: start, index: 2)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        viewModel.goToToday(asOf: day(0))
        return viewModel
    }

    /// Adds a macro and meso spanning `lengths.count` consecutive micro-cycles of the given lengths,
    /// with the micro at `index` starting on `anchoredAt`.
    private func seedPlan(
        _ model: TrainingModel, lengths: [Int], anchoredAt anchor: Date, index: Int,
        phase: CyclePhase = .build
    ) async throws {
        let calendar = calendar(model)
        var cursor = calendar.date(byAdding: .day, value: -lengths[..<index].reduce(0, +), to: anchor)!
        var micros: [(Date, Date)] = []
        for length in lengths {
            let last = calendar.date(byAdding: .day, value: length - 1, to: cursor)!
            micros.append((cursor, last))
            cursor = calendar.date(byAdding: .day, value: length, to: cursor)!
        }
        let whole = micros.first!.0...micros.last!.1
        let macro = TrainingCycle(level: .macro, phase: .build, name: "Ultra prep", dateRange: whole)
        let meso = TrainingCycle(level: .meso, phase: phase, name: "Build 1", dateRange: whole, parentID: macro.id)
        let cycles = micros.enumerated().map { offset, range in
            TrainingCycle(
                level: .micro, phase: phase, name: "Micro \(offset + 1)",
                dateRange: range.0...range.1, parentID: meso.id
            )
        }
        try await model.add([macro, meso] + cycles)
    }

    private func calendar(_ model: TrainingModel) -> Calendar {
        WeekViewModel.calendar(for: model.athlete)
    }

    private func dayCount(_ range: ClosedRange<Date>, _ calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: range.lowerBound, to: range.upperBound).day! + 1
    }

    @Test("a calendar week is 7 days starting on the athlete's week-start day")
    func calendarWeekFactory() {
        let calendar = calendar(makeModel())
        let week = DisplayPeriod.calendarWeek(containing: day(3), calendar: calendar)

        #expect(week.lengthInDays == 7)
        #expect(calendar.component(.weekday, from: week.start) == Weekday.monday.rawValue)
    }

    @Test("a length below 1 is raised to 1")
    func lengthIsClamped() {
        #expect(DisplayPeriod(start: day(0), lengthInDays: 0).lengthInDays == 1)
    }

    @Test("days, last day, neighbors, chart, load and highlight ranges scale with the length", arguments: [7, 10, 14])
    func periodGeometry(length: Int) {
        let calendar = calendar(makeModel())
        let period = DisplayPeriod(start: calendar.startOfDay(for: day(0)), lengthInDays: length)

        #expect(period.days(calendar: calendar).count == length)
        #expect(period.days(calendar: calendar).first == period.start)
        #expect(period.days(calendar: calendar).last == period.lastDay(calendar: calendar))
        #expect(period.next(calendar: calendar).start == calendar.date(byAdding: .day, value: length, to: period.start))
        #expect(period.previous(calendar: calendar).next(calendar: calendar) == period)

        let chart = period.chartRange(calendar: calendar)
        #expect(dayCount(chart, calendar) == 3 * length)
        #expect(chart.lowerBound == period.previous(calendar: calendar).start)
        #expect(chart.upperBound == period.next(calendar: calendar).lastDay(calendar: calendar))

        let load = period.loadRange(calendar: calendar)
        #expect(dayCount(load, calendar) == 5 * length)
        #expect(period.highlightRange(calendar: calendar).upperBound == period.next(calendar: calendar).start)
    }

    @Test("the view model's ranges, days and navigation follow the displayed length", arguments: [7, 10, 14])
    func viewModelFollowsLength(length: Int) async throws {
        let model = makeModel()
        let calendar = calendar(model)
        let viewModel = try await uniformViewModel(model, length: length)
        let start = viewModel.displayedWeekStart

        #expect(viewModel.weekDates.count == length)
        #expect(viewModel.weekDates(offsetWeeks: 1).first == calendar.date(byAdding: .day, value: length, to: start))
        #expect(viewModel.weekDates(offsetWeeks: -1).first == calendar.date(byAdding: .day, value: -length, to: start))
        #expect(dayCount(viewModel.chartRange, calendar) == 3 * length)
        #expect(viewModel.chartRange.lowerBound == calendar.date(byAdding: .day, value: -length, to: start))
        #expect(viewModel.displayedWeekRange.upperBound == calendar.date(byAdding: .day, value: length, to: start))

        viewModel.goToNextWeek()
        #expect(viewModel.displayedWeekStart == calendar.date(byAdding: .day, value: length, to: start))
        viewModel.goToPreviousWeek()
        viewModel.goToPreviousWeek()
        #expect(viewModel.displayedWeekStart == calendar.date(byAdding: .day, value: -length, to: start))
    }

    @Test("the displayed period defaults to a calendar week")
    func defaultsToCalendarWeek() {
        let model = makeModel()
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        #expect(viewModel.displayedPeriod.lengthInDays == 7)
        #expect(viewModel.displayedPeriod.start == viewModel.displayedWeekStart)
    }

    @Test("the date range description ends on the period's last day", arguments: [7, 10, 14])
    func descriptionEndsOnLastDay(length: Int) async throws {
        let model = makeModel()
        let calendar = calendar(model)
        let viewModel = try await uniformViewModel(model, length: length)
        let last = viewModel.displayedPeriod.lastDay(calendar: calendar)
        let expected = last.formatted(
            Date.FormatStyle(calendar: calendar, timeZone: viewModel.athleteTimeZone).day().month(.abbreviated).year()
        )

        #expect(viewModel.displayedWeekDateRangeDescription.hasSuffix(expected))
    }

    @Test("the cache window is the displayed period and one neighbor either side", arguments: [7, 10, 14])
    func cacheWindowFollowsLength(length: Int) async throws {
        let model = makeModel()
        let calendar = calendar(model)
        let viewModel = try await uniformViewModel(model, length: length)
        await viewModel.refreshWeekCachesIfNeeded(asOf: day(0))

        let period = viewModel.displayedPeriod
        #expect(viewModel.cachedPeriods == [period.previous(calendar: calendar), period, period.next(calendar: calendar)])
        #expect(Set(viewModel.weekGraphCaches.keys) == Set(viewModel.cachedPeriods))
    }

    @Test("caches for the same start date but another length are separate entries")
    func cachesAreKeyedByLength() {
        let start = day(0)
        #expect(DisplayPeriod(start: start, lengthInDays: 7) != DisplayPeriod(start: start, lengthInDays: 10))
    }

    @Test("the stats pages compare against the previous period of the same length", arguments: [7, 10, 14])
    func statsCompareWithPreviousPeriod(length: Int) async throws {
        let model = makeModel()
        let viewModel = try await uniformViewModel(model, length: length)
        // No data: the pages still build for any length, with nothing to compare.
        let pages = viewModel.sportStatsPages(for: viewModel.displayedWeekStart, asOf: day(0))
        #expect(!pages.isEmpty)
    }

    // MARK: Planned micro-cycles (MVP5-107)

    private func start(of micro: Int, lengths: [Int], first: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: lengths[..<micro].reduce(0, +), to: first)!
    }

    @Test("a date inside a 10- or 14-day micro shows that micro, a date outside shows the calendar week", arguments: [10, 14])
    func microContainingDate(length: Int) async throws {
        let model = makeModel()
        let calendar = calendar(model)
        let first = WeekViewModel.weekStart(containing: day(0), calendar: calendar)
        let lengths = [length, 7, length]
        try await seedPlan(model, lengths: lengths, anchoredAt: first, index: 0)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        viewModel.goToWeek(containing: calendar.date(byAdding: .day, value: length - 1, to: first)!)
        #expect(viewModel.displayedPeriod == DisplayPeriod(start: first, lengthInDays: length))
        #expect(viewModel.weekDates.count == length)

        let outside = calendar.date(byAdding: .day, value: 3 * length + 20, to: first)!
        viewModel.goToWeek(containing: outside)
        #expect(viewModel.displayedPeriod == DisplayPeriod.calendarWeek(containing: outside, calendar: calendar))
    }

    @Test("paging crosses micro, 7-day micro and calendar-week boundaries in both directions")
    func pagingAcrossBoundaries() async throws {
        let model = makeModel()
        let calendar = calendar(model)
        let first = WeekViewModel.weekStart(containing: day(0), calendar: calendar)
        let lengths = [10, 14, 7]
        try await seedPlan(model, lengths: lengths, anchoredAt: first, index: 0)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        viewModel.goToWeek(containing: first)

        var starts: [Date] = [viewModel.displayedWeekStart]
        var seen: [Int] = [viewModel.displayedLengthInDays]
        for _ in 0..<4 {
            viewModel.goToNextWeek()
            starts.append(viewModel.displayedWeekStart)
            seen.append(viewModel.displayedLengthInDays)
        }
        // 10 → 14 → 7 (planned), then the rest of that calendar week (4 days) and whole weeks.
        #expect(seen == [10, 14, 7, 4, 7])
        #expect(starts[1] == calendar.date(byAdding: .day, value: 10, to: first))
        #expect(starts[2] == calendar.date(byAdding: .day, value: 24, to: first))
        #expect(starts[3] == calendar.date(byAdding: .day, value: 31, to: first))

        for expected in starts.dropLast().reversed() {
            viewModel.goToPreviousWeek()
            #expect(viewModel.displayedWeekStart == expected)
        }
        #expect(viewModel.displayedLengthInDays == 10)
    }

    @Test("neighbors come from the plan, so the chart and load windows follow their lengths")
    func neighborsDifferInLength() async throws {
        let model = makeModel()
        let calendar = calendar(model)
        let first = WeekViewModel.weekStart(containing: day(0), calendar: calendar)
        let lengths = [7, 10, 14, 7, 10]
        try await seedPlan(model, lengths: lengths, anchoredAt: first, index: 0)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        viewModel.goToWeek(containing: calendar.date(byAdding: .day, value: 7, to: first)!) // the 10-day micro

        #expect(dayCount(viewModel.chartRange, calendar) == 7 + 10 + 14)
        #expect(dayCount(viewModel.chartRange(for: viewModel.displayedWeekStart), calendar) == 31)
        let load = viewModel.chartRange.lowerBound
        #expect(load == first)
        #expect(viewModel.cachedPeriods.map(\.lengthInDays) == [7, 10, 14])
        #expect(viewModel.weekDates(offsetWeeks: 1).count == 14)
        #expect(viewModel.weekDates(offsetWeeks: -1).count == 7)
    }

    @Test("a calendar week next to a micro is cut short so periods never overlap")
    func calendarWeekIsClippedAtMicro() async throws {
        let model = makeModel()
        let calendar = calendar(model)
        let monday = WeekViewModel.weekStart(containing: day(0), calendar: calendar)
        // A 10-day micro starting on the Thursday after `monday`.
        let microStart = calendar.date(byAdding: .day, value: 10, to: monday)!
        try await seedPlan(model, lengths: [10], anchoredAt: microStart, index: 0)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        viewModel.goToWeek(containing: calendar.date(byAdding: .day, value: 8, to: monday)!)
        let before = viewModel.displayedPeriod
        #expect(before.lastDay(calendar: calendar) == calendar.date(byAdding: .day, value: -1, to: microStart))
        viewModel.goToNextWeek()
        #expect(viewModel.displayedWeekStart == microStart)
        viewModel.goToNextWeek()
        // The week after the micro starts the day after it, not on a Monday.
        #expect(viewModel.displayedWeekStart == calendar.date(byAdding: .day, value: 10, to: microStart))
    }

    @Test("the header context names macro, meso, micro, phase and the week in the plan")
    func cycleContextHeader() async throws {
        let model = makeModel()
        let calendar = calendar(model)
        let first = WeekViewModel.weekStart(containing: day(0), calendar: calendar)
        try await seedPlan(model, lengths: [7, 10, 14], anchoredAt: first, index: 0, phase: "ultra-specific")
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))

        viewModel.goToWeek(containing: calendar.date(byAdding: .day, value: 12, to: first)!)
        let context = try #require(viewModel.cycleContext())
        #expect(context.breadcrumb == "Ultra prep › Build 1 › Micro 2")
        #expect(context.weekInPlan == 2)
        #expect(context.lengthInDays == 10)
        #expect(context.phase == "ultra-specific")
        #expect(context.phaseTitle == "Ultra-Specific")
        #expect(context.loadRole == .build)
        #expect(viewModel.displayedTitle == "Week 2")

        viewModel.goToWeek(containing: calendar.date(byAdding: .day, value: 300, to: first)!)
        #expect(viewModel.cycleContext() == nil)
        #expect(viewModel.displayedTitle == "Week \(viewModel.displayedWeekOfYear)")
    }

    @Test("a plan that loads after the jump switches the calendar week to its micro")
    func loadRefreshesDisplayedPeriod() async throws {
        let model = makeModel()
        let calendar = calendar(model)
        let first = WeekViewModel.weekStart(containing: day(0), calendar: calendar)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: day(0))
        #expect(viewModel.displayedLengthInDays == 7)

        try await seedPlan(model, lengths: [14], anchoredAt: first, index: 0)
        await viewModel.load(asOf: day(0))

        #expect(viewModel.displayedPeriod == DisplayPeriod(start: first, lengthInDays: 14))
    }

    @Test("a 10-day micro across the autumn DST change keeps 10 calendar days and pages cleanly")
    func dstBoundary() async throws {
        let model = makeModel(timeZone: "Europe/Amsterdam")
        let calendar = calendar(model)
        // Clocks go back on 2026-10-25, a 25-hour day inside the micro.
        let micro = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22))!
        try await seedPlan(model, lengths: [7, 10, 14], anchoredAt: micro, index: 1)
        let viewModel = WeekViewModel(model: model, refresher: FakeRefresher(), today: micro)
        viewModel.goToWeek(containing: calendar.date(from: DateComponents(year: 2026, month: 10, day: 26))!)

        let period = viewModel.displayedPeriod
        #expect(period == DisplayPeriod(start: micro, lengthInDays: 10))
        let days = viewModel.weekDates
        #expect(days.count == 10)
        #expect(days.allSatisfy { calendar.startOfDay(for: $0) == $0 })
        #expect(calendar.component(.day, from: days[3]) == 25)
        #expect(calendar.dateComponents([.hour], from: days[3], to: days[4]).hour == 25)
        #expect(calendar.component(.day, from: period.lastDay(calendar: calendar)) == 31)

        viewModel.goToNextWeek()
        #expect(viewModel.displayedWeekStart == calendar.date(from: DateComponents(year: 2026, month: 11, day: 1)))
        #expect(viewModel.displayedLengthInDays == 14)
        viewModel.goToPreviousWeek()
        #expect(viewModel.displayedPeriod == period)
    }
}
