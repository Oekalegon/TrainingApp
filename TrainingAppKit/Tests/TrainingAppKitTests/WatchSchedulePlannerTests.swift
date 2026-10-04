import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@Suite("WatchSchedulePlanner")
struct WatchSchedulePlannerTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        return calendar
    }()

    /// 2026-10-04 10:00 in Amsterdam.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 10))!
    }

    /// The start of the day `offset` days from `now`'s, in Amsterdam.
    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
    }

    private func plan(on date: Date, completed: Bool = false) -> PlannedActivity {
        PlannedActivity(workoutID: UUID(), date: date, completedActivityID: completed ? UUID() : nil)
    }

    private func plan(_ plans: [PlannedActivity], cap: Int = 15, canSchedule: (PlannedActivity) -> Bool = { _ in true }) -> WatchSchedulePlanner.Result {
        WatchSchedulePlanner.plan(plans, asOf: now, calendar: calendar, cap: cap, canSchedule: canSchedule)
    }

    @Test("the window runs from the start of today to the end of the 7th day, in the athlete's time zone")
    func windowEdges() {
        #expect(WatchSchedulePlanner.isInWindow(day(0), asOf: now, calendar: calendar))
        #expect(WatchSchedulePlanner.isInWindow(day(7).addingTimeInterval(-1), asOf: now, calendar: calendar))
        #expect(!WatchSchedulePlanner.isInWindow(day(7), asOf: now, calendar: calendar))
        #expect(!WatchSchedulePlanner.isInWindow(day(0).addingTimeInterval(-1), asOf: now, calendar: calendar))
    }

    @Test("the window keeps whole days across a daylight-saving change")
    func windowAcrossDaylightSavingChange() {
        // Amsterdam leaves summer time on 2026-10-25, so that day is 25 hours long.
        let beforeChange = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9))!
        let lastDay = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 23))!
        let dayAfter = calendar.date(from: DateComponents(year: 2026, month: 10, day: 27))!
        #expect(WatchSchedulePlanner.isInWindow(lastDay, asOf: beforeChange, calendar: calendar))
        #expect(!WatchSchedulePlanner.isInWindow(dayAfter, asOf: beforeChange, calendar: calendar))
    }

    @Test("schedules the unlinked plans of the next 7 days, soonest first, and keeps only those")
    func schedulesUpcomingPlans() {
        let yesterday = plan(on: day(-1))
        let today = plan(on: day(0))
        let sixDaysOut = plan(on: day(6))
        let tomorrow = plan(on: day(1))
        let sevenDaysOut = plan(on: day(7))

        let result = plan([yesterday, today, sixDaysOut, tomorrow, sevenDaysOut])

        #expect(result.toSchedule.map(\.id) == [today.id, tomorrow.id, sixDaysOut.id])
        #expect(result.keep == [today.id, tomorrow.id, sixDaysOut.id])
    }

    @Test("leaves out plans whose workout can't go on the Watch")
    func skipsUnschedulablePlans() {
        let good = plan(on: day(1))
        let bad = plan(on: day(2))

        let result = plan([good, bad]) { $0.id != bad.id }

        #expect(result.toSchedule.map(\.id) == [good.id])
        #expect(result.keep == [good.id])
    }

    @Test("keeps completed plans of the last 7 days without scheduling them; older ones go")
    func keepsRecentlyCompletedPlans() {
        let doneToday = plan(on: day(0), completed: true)
        let doneLastWeek = plan(on: day(-7), completed: true)
        let doneLongAgo = plan(on: day(-8), completed: true)
        let missed = plan(on: day(-2))

        let result = plan([doneToday, doneLastWeek, doneLongAgo, missed])

        #expect(result.toSchedule.isEmpty)
        #expect(result.keep == [doneToday.id, doneLastWeek.id])
    }

    @Test("the cap goes to upcoming plans first, then to the most recently completed ones")
    func capPrefersUpcomingPlans() {
        let upcoming = (0..<3).map { plan(on: day($0)) }
        let recent = plan(on: day(-1), completed: true)
        let older = plan(on: day(-3), completed: true)

        let result = plan(upcoming + [older, recent], cap: 4)

        #expect(result.toSchedule.map(\.id) == upcoming.map(\.id))
        #expect(result.keep == Set(upcoming.map(\.id) + [recent.id]))
    }

    @Test("past the cap, the soonest upcoming plans win")
    func capKeepsSoonestPlans() {
        let upcoming = (0..<5).map { plan(on: day($0)) }

        let result = plan(upcoming.reversed(), cap: 2)

        #expect(result.toSchedule.map(\.id) == upcoming.prefix(2).map(\.id))
        #expect(result.keep == Set(upcoming.prefix(2).map(\.id)))
    }
}
