import Foundation
import TrainingCore

/// Splits a day-ordered series of `FitnessMetrics` into "past" (actual history) and "future"
/// (projected/estimated) halves around `today`, for `FitnessChartView` to render as solid vs.
/// dashed lines.
enum FitnessMetricsSplit {
    /// - Returns: `past` (every day up to and including `today`) and `future` (`today` onward).
    ///   `today` itself appears in both halves — deliberately, not an off-by-one — so the solid
    ///   and dashed line segments a caller draws from these connect with no visual gap. `metrics`
    ///   need not already be sorted; this sorts by day first.
    static func pastAndFuture(
        _ metrics: [FitnessMetrics],
        today: Date
    ) -> (past: [FitnessMetrics], future: [FitnessMetrics]) {
        let sorted = metrics.sorted { $0.day < $1.day }
        guard let splitIndex = sorted.lastIndex(where: { $0.day <= today }) else {
            return ([], sorted)
        }
        return (Array(sorted[0...splitIndex]), Array(sorted[splitIndex...]))
    }
}
