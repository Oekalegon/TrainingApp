import Testing
@testable import TrainingAppKit

@Suite("HeartRateZoneBarChartView")
struct HeartRateZoneBarChartViewTests {
    @Test("domainUpperBound(forMaxMinutes:) pads past the longest bar's own value")
    func domainUpperBoundPadsPastMaxMinutes() {
        // Regression test for MVP1-78: without this headroom, the longest bar's value mapped
        // exactly to the plot's own right edge, leaving its own trailing annotation nowhere to draw.
        let domainUpperBound = HeartRateZoneBarChartView.domainUpperBound(forMaxMinutes: 100)
        #expect(domainUpperBound > 100)
    }

    @Test("domainUpperBound(forMaxMinutes:) floors at 1 even when every zone is empty")
    func domainUpperBoundFloorsAtOneWhenEmpty() {
        let domainUpperBound = HeartRateZoneBarChartView.domainUpperBound(forMaxMinutes: 0)
        #expect(domainUpperBound > 0)
    }

    @Test("barLength(_:domainUpperBound:chartWidth:) passes real, positive minutes through unchanged")
    func barLengthPassesRealMinutesThrough() {
        let length = HeartRateZoneBarChartView.barLength(42, domainUpperBound: 130, chartWidth: 300)
        #expect(length == 42)
    }

    @Test("barLength(_:domainUpperBound:chartWidth:) maps a zero-minute zone to a hairline, not zero")
    func barLengthGivesZeroMinuteZoneAHairline() {
        let length = HeartRateZoneBarChartView.barLength(0, domainUpperBound: 130, chartWidth: 300)
        #expect(length > 0)
        // 1 pixel wide out of 300, scaled back into the domain's own units.
        #expect(length == 130.0 * (1.0 / 300.0))
    }

    @Test("barLength(_:domainUpperBound:chartWidth:) is 0 when the chart hasn't measured its width yet")
    func barLengthIsZeroWithoutChartWidth() {
        let length = HeartRateZoneBarChartView.barLength(0, domainUpperBound: 130, chartWidth: 0)
        #expect(length == 0)
    }
}
