import Foundation
import Testing
import TrainingCore
@testable import TrainingAppKit

@Suite("DailyLoad")
struct DailyLoadTests {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86400)
    }

    private func metrics(day: Date, load: Double) -> FitnessMetrics {
        FitnessMetrics(
            day: day,
            load: load,
            ctl: 0,
            atl: 0,
            tsb: 0,
            monotony: .nan,
            strain: .nan,
            isProjected: false,
            isWarmingUp: false
        )
    }

    @Test("Rest days (load 0) are dropped")
    func restDaysDropped() {
        let result = DailyLoad.aggregating([metrics(day: day(0), load: 0)])
        #expect(result.isEmpty)
    }

    @Test("Empty metrics produces no daily loads")
    func emptyMetrics() {
        #expect(DailyLoad.aggregating([]).isEmpty)
    }

    @Test("Multiple entries for the same day are summed, not shown as separate dots")
    func duplicateDayEntriesAreSummed() {
        let result = DailyLoad.aggregating([
            metrics(day: day(0), load: 40),
            metrics(day: day(0), load: 25),
        ])
        #expect(result.count == 1)
        #expect(result.first?.load == 65)
    }

    @Test("Result is sorted by day regardless of input order")
    func sortedByDay() {
        let result = DailyLoad.aggregating([
            metrics(day: day(2), load: 10),
            metrics(day: day(0), load: 20),
            metrics(day: day(1), load: 30),
        ])
        #expect(result.map(\.day) == [day(0), day(1), day(2)])
    }
}
