import TrainingCore

/// Everything a metric detail chart draws for one range (MVP2-137): the fitness metrics, the
/// planned-vs-performed daily load and the race markers, as `MicroCycleViewModel.chartBuffer(in:asOf:)`
/// returns them together.
struct ChartBuffer {
    /// `MicroCycleViewModel.metrics(in:asOf:)` for the range.
    let metrics: [FitnessMetrics]
    /// `MicroCycleViewModel.dailyLoadSplit(in:asOf:)` for the range.
    let dailyLoadSplit: DailyLoadSplit
    /// `MicroCycleViewModel.chartRaces(in:)` for the range.
    let races: [Race]
}
