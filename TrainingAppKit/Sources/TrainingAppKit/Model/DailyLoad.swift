import Foundation
import TrainingCore

/// One calendar day's total training load, for `FitnessChartView`'s daily-load dots.
struct DailyLoad: Hashable {
    let day: Date
    let load: Double

    /// One entry per calendar day with an actual training load, loads summed if `metrics` has
    /// more than one entry for the same day — `FitnessMetrics.day` is meant to be unique per day
    /// (`FitnessMetricsCalculator` produces exactly one row per input day), but a duplicate-row
    /// bug upstream (the same class of concurrent-upsert race `MVP1-26` fixed for activities) can
    /// still surface as several separate rows for one day, each carrying a single activity's load
    /// instead of the day's total. Summing here shows the correct daily TRIMP regardless, though
    /// the root cause still belongs in TrainingKit's `FitnessMetricsCacheStore.upsert`. Days with
    /// no load (rest days) are dropped, since a dot at zero carries no information.
    static func aggregating(_ metrics: [FitnessMetrics]) -> [DailyLoad] {
        var totals: [Date: Double] = [:]
        for point in metrics {
            totals[point.day, default: 0] += point.load
        }
        return totals
            .filter { $0.value > 0 }
            .map { DailyLoad(day: $0.key, load: $0.value) }
            .sorted { $0.day < $1.day }
    }
}
