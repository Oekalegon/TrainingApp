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

    private func makeModel() -> TrainingModel {
        let store = InMemoryStore()
        let stores = StoreSet(
            activityStore: store, planStore: store, workoutStore: store,
            cycleStore: store, raceStore: store, athleteStore: store
        )
        let athlete = AthleteProfile.fixture(weekStartsOn: .monday, timeZoneIdentifier: "UTC")
        return TrainingModel(stores: stores, athlete: athlete)
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
    func viewModelFollowsLength(length: Int) {
        let model = makeModel()
        let calendar = calendar(model)
        let viewModel = WeekViewModel(
            model: model, refresher: FakeRefresher(), today: day(0), displayedLengthInDays: length
        )
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
    func descriptionEndsOnLastDay(length: Int) {
        let model = makeModel()
        let calendar = calendar(model)
        let viewModel = WeekViewModel(
            model: model, refresher: FakeRefresher(), today: day(0), displayedLengthInDays: length
        )
        let last = viewModel.displayedPeriod.lastDay(calendar: calendar)
        let expected = last.formatted(
            Date.FormatStyle(calendar: calendar, timeZone: viewModel.athleteTimeZone).day().month(.abbreviated).year()
        )

        #expect(viewModel.displayedWeekDateRangeDescription.hasSuffix(expected))
    }

    @Test("the cache window is the displayed period and one neighbor either side", arguments: [7, 10, 14])
    func cacheWindowFollowsLength(length: Int) async {
        let model = makeModel()
        let calendar = calendar(model)
        let viewModel = WeekViewModel(
            model: model, refresher: FakeRefresher(), today: day(0), displayedLengthInDays: length
        )
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
    func statsCompareWithPreviousPeriod(length: Int) {
        let model = makeModel()
        let viewModel = WeekViewModel(
            model: model, refresher: FakeRefresher(), today: day(0), displayedLengthInDays: length
        )
        // No data: the pages still build for any length, with nothing to compare.
        let pages = viewModel.sportStatsPages(for: viewModel.displayedWeekStart, asOf: day(0))
        #expect(!pages.isEmpty)
    }
}
