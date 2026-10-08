import TrainingCore

/// Everything a metric detail chart draws for one range (MVP2-137): the fitness metrics, the
/// planned-vs-performed daily load and the race markers, as `WeekViewModel.chartBuffer(in:asOf:)`
/// returns them together.
struct ChartBuffer {
    /// `WeekViewModel.metrics(in:asOf:)` for the range.
    let metrics: [FitnessMetrics]
    /// `WeekViewModel.dailyLoadSplit(in:asOf:)` for the range.
    let dailyLoadSplit: DailyLoadSplit
    /// `WeekViewModel.chartRaces(in:)` for the range.
    let races: [Race]
}
