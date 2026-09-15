import Foundation
import Testing
@testable import TrainingAppKit

@Suite("ChartAxisMarks")
struct ChartAxisMarksTests {
    /// Monday-start ISO calendar, matching this app's typical athlete default.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)!
    }

    @Test(".week and .month put gridlines on each visible week's own start")
    func weekAndMonthAlignToWeekStarts() {
        // 2026-09-14 is a Monday; the domain spans three full weeks.
        let domain = date(2026, 9, 10)...date(2026, 9, 29)

        for period: ChartPeriod in [.week, .month] {
            let marks = ChartAxisMarks.dates(for: period, in: domain, calendar: calendar)
            #expect(marks == [date(2026, 9, 14), date(2026, 9, 21), date(2026, 9, 28)])
            for mark in marks {
                #expect(calendar.component(.weekday, from: mark) == calendar.firstWeekday)
            }
        }
    }

    @Test(".threeMonths and .sixMonths put gridlines on each visible month's own first day")
    func threeAndSixMonthsAlignToMonthStarts() {
        let domain = date(2026, 6, 15)...date(2026, 9, 15)

        for period: ChartPeriod in [.threeMonths, .sixMonths] {
            let marks = ChartAxisMarks.dates(for: period, in: domain, calendar: calendar)
            #expect(marks == [date(2026, 7, 1), date(2026, 8, 1), date(2026, 9, 1)])
        }
    }

    @Test(".year only puts gridlines on January, April, July and September")
    func yearAlignsToFixedQuarterlyMonths() {
        let domain = date(2025, 11, 1)...date(2026, 12, 1)

        let marks = ChartAxisMarks.dates(for: .year, in: domain, calendar: calendar)

        #expect(marks == [
            date(2026, 1, 1), date(2026, 4, 1), date(2026, 7, 1), date(2026, 9, 1),
        ])
    }

    @Test("dates(for:in:calendar:) excludes a boundary that falls outside the domain")
    func excludesBoundariesOutsideDomain() {
        // Starts mid-week and mid-year, so the very first week/month/quarter boundary is excluded.
        let weekDomain = date(2026, 9, 15)...date(2026, 9, 20)
        #expect(ChartAxisMarks.dates(for: .week, in: weekDomain, calendar: calendar).isEmpty)

        let yearDomain = date(2026, 2, 1)...date(2026, 3, 1)
        #expect(ChartAxisMarks.dates(for: .year, in: yearDomain, calendar: calendar).isEmpty)
    }

    @Test("labelText(for:period:calendar:) includes the day number for .week/.month, not for 3M/6M/Year")
    func labelTextOmitsDayNumberPastMonthGranularity() {
        let weekStart = date(2026, 9, 14)

        #expect(ChartAxisMarks.labelText(for: weekStart, period: .week, calendar: calendar) == "Sep 14")
        #expect(ChartAxisMarks.labelText(for: weekStart, period: .month, calendar: calendar) == "Sep 14")
        #expect(ChartAxisMarks.labelText(for: weekStart, period: .threeMonths, calendar: calendar) == "Sep")
        #expect(ChartAxisMarks.labelText(for: weekStart, period: .sixMonths, calendar: calendar) == "Sep")
        #expect(ChartAxisMarks.labelText(for: weekStart, period: .year, calendar: calendar) == "Sep")
    }

    @Test("labelText(for:period:calendar:) appends the year only for a January gridline, past .week/.month")
    func labelTextAppendsYearOnlyForJanuary() {
        for period: ChartPeriod in [.threeMonths, .sixMonths, .year] {
            #expect(ChartAxisMarks.labelText(for: date(2026, 1, 1), period: period, calendar: calendar) == "Jan 2026")
            #expect(ChartAxisMarks.labelText(for: date(2026, 4, 1), period: period, calendar: calendar) == "Apr")
        }
        // .week/.month always carry a day number, never the year, no matter the month.
        #expect(ChartAxisMarks.labelText(for: date(2026, 1, 5), period: .week, calendar: calendar) == "Jan 5")
    }
}
