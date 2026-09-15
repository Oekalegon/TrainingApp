import Foundation
import Testing
@testable import TrainingAppKit

@Suite("ChartPanState")
struct ChartPanStateTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    @Test("bufferRange(around:period:calendar:) is three times as wide as period's own range, centered on it")
    func bufferRangeTriplesPeriodRange() {
        let calendar = utc
        let anchor = day(0)
        let state = ChartPanState(anchorDate: anchor, loadedRange: anchor...anchor)

        let base = ChartPeriod.week.range(around: anchor, calendar: calendar)
        let span = base.upperBound.timeIntervalSince(base.lowerBound)
        let buffer = state.bufferRange(around: anchor, period: .week, calendar: calendar)

        #expect(buffer.lowerBound == base.lowerBound.addingTimeInterval(-span))
        #expect(buffer.upperBound == base.upperBound.addingTimeInterval(span))
    }

    @Test("panAnchor(for:period:calendar:) moves the anchor backward (into the past) for a rightward (positive) drag")
    func panAnchorRightwardDragRevealsThePast() {
        let calendar = utc
        let anchor = day(100)
        var state = ChartPanState(
            anchorDate: anchor,
            loadedRange: day(0)...day(200),
            chartWidth: 280
        )

        let result = state.panAnchor(for: 28, period: .week, calendar: calendar)

        #expect(result < anchor)
    }

    @Test("panAnchor(for:period:calendar:) moves the anchor forward (into the future) for a leftward (negative) drag")
    func panAnchorLeftwardDragRevealsTheFuture() {
        let calendar = utc
        let anchor = day(100)
        let state = ChartPanState(
            anchorDate: anchor,
            loadedRange: day(0)...day(200),
            chartWidth: 280
        )

        let result = state.panAnchor(for: -28, period: .week, calendar: calendar)

        #expect(result > anchor)
    }

    @Test("panAnchor(for:period:calendar:) is a no-op for zero translation or an unmeasured (≤1pt) chart width")
    func panAnchorNoOpWithoutRealInput() {
        let calendar = utc
        let anchor = day(100)
        let measured = ChartPanState(anchorDate: anchor, loadedRange: day(0)...day(200), chartWidth: 280)
        let unmeasured = ChartPanState(anchorDate: anchor, loadedRange: day(0)...day(200), chartWidth: 1)

        #expect(measured.panAnchor(for: 0, period: .week, calendar: calendar) == anchor)
        #expect(unmeasured.panAnchor(for: 50, period: .week, calendar: calendar) == anchor)
    }

    @Test("clamped(_:period:calendar:) keeps period.range(around:) fully inside loadedRange")
    func clampedStaysInsideLoadedRange() {
        let calendar = utc
        let loadedRange = day(0)...day(200)
        let state = ChartPanState(anchorDate: day(100), loadedRange: loadedRange)

        // Far outside the loaded buffer on both sides.
        let clampedEarly = state.clamped(day(-1000), period: .week, calendar: calendar)
        let clampedLate = state.clamped(day(1000), period: .week, calendar: calendar)

        let earlyRange = ChartPeriod.week.range(around: clampedEarly, calendar: calendar)
        let lateRange = ChartPeriod.week.range(around: clampedLate, calendar: calendar)
        #expect(earlyRange.lowerBound >= loadedRange.lowerBound)
        #expect(lateRange.upperBound <= loadedRange.upperBound)
    }

    @Test("clamped(_:period:calendar:) leaves the candidate untouched when it already fits inside loadedRange")
    func clampedLeavesInBoundsCandidateAlone() {
        let calendar = utc
        let state = ChartPanState(anchorDate: day(100), loadedRange: day(0)...day(200))

        let candidate = day(105)
        #expect(state.clamped(candidate, period: .week, calendar: calendar) == candidate)
    }

    @Test("clamped(_:period:calendar:) refuses to move (returns anchorDate) when loadedRange is too narrow for period to fit at all")
    func clampedRefusesToMoveWhenLoadedRangeTooNarrow() {
        let calendar = utc
        let anchor = day(0)
        // A zero-width loadedRange -- e.g. `ChartDayDomain.range(for:)`'s own `now...now` fallback
        // for an empty `chartContext.metrics` right after `MetricDetailView` first appears.
        let state = ChartPanState(anchorDate: anchor, loadedRange: anchor...anchor)

        #expect(state.clamped(day(50), period: .week, calendar: calendar) == anchor)
    }
}
