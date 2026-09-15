import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@Suite("MetricDetailSubject")
struct MetricDetailSubjectTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func metrics(day: Date, load: Double) -> FitnessMetrics {
        FitnessMetrics(
            day: day, load: load, ctl: 0, atl: 0, tsb: 0,
            monotony: .nan, strain: .nan, isProjected: false, isWarmingUp: false
        )
    }

    @Test(".day subject's metrics(in:calendar:) returns only that day's own point")
    func dayReturnsOnlyThatDay() {
        let all = [
            metrics(day: day(0), load: 10),
            metrics(day: day(1), load: 20),
            metrics(day: day(2), load: 30),
        ]

        let result = MetricDetailSubject.day(day(1)).metrics(in: all, calendar: calendar)

        #expect(result.map(\.load) == [20])
    }

    @Test(".week subject's metrics(in:calendar:) includes every day from the start up to (not including) the end")
    func weekIncludesSevenDaysHalfOpen() {
        let weekStart = day(0)
        let weekRange = weekStart...day(7)
        let all = (0...7).map { metrics(day: day($0), load: Double($0)) }

        let result = MetricDetailSubject.week(weekRange).metrics(in: all, calendar: calendar)

        // day(7) is the *next* week's own start (range.upperBound), not part of this week.
        #expect(result.map(\.load) == [0, 1, 2, 3, 4, 5, 6])
    }

    @Test(".week subject's metrics(in:calendar:) excludes a point exactly on range.upperBound")
    func weekExcludesUpperBoundExactly() {
        let weekRange = day(0)...day(7)
        let all = [metrics(day: day(7), load: 999)]

        let result = MetricDetailSubject.week(weekRange).metrics(in: all, calendar: calendar)

        #expect(result.isEmpty)
    }

    // Both tests below check substrings, not the full formatted string -- `dateText(calendar:)`
    // deliberately follows the device's own locale (unlike `ChartAxisMarks.labelText`, which pins
    // one), so "September 15" vs. "15 September" both are correct depending on the host's own
    // locale; asserting exact word order would make these tests fail on a non-US-ordering machine
    // without the underlying behavior having changed at all.

    @Test(".day subject's dateText(calendar:) spells out the weekday, full month name, day and year")
    func dayDateTextIsFullySpelledOut() {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 15
        let tuesday = calendar.date(from: components)!

        let text = MetricDetailSubject.day(tuesday).dateText(calendar: calendar)

        #expect(text.contains("Tuesday"))
        #expect(text.contains("September"))
        #expect(text.contains("15"))
        #expect(text.contains("2026"))
    }

    @Test(".week subject's dateText(calendar:) shows the range's own last actual day, not range.upperBound")
    func weekDateTextUsesLastActualDay() {
        var start = DateComponents()
        start.year = 2026
        start.month = 9
        start.day = 14
        let weekStart = calendar.date(from: start)!
        let weekRange = weekStart...calendar.date(byAdding: .day, value: 7, to: weekStart)!

        let text = MetricDetailSubject.week(weekRange).dateText(calendar: calendar)

        #expect(text.contains("Sep"))
        #expect(text.contains("14"))
        // The week's own last actual day is the 20th -- range.upperBound (the 21st, the *next*
        // week's own start) must never appear here.
        #expect(text.contains("20"))
        #expect(!text.contains("21"))
        #expect(text.contains("2026"))
        // The year appears exactly once, not on both ends of a week that doesn't cross a boundary.
        #expect(text.components(separatedBy: "2026").count == 2)
    }
}
