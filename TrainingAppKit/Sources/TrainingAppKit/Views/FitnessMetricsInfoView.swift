import SwiftUI
import TrainingCore

/// The sheet chrome around `MetricDetailView` (MVP1-45) — a `NavigationStack` (for a later
/// "Options" section to push into, and standard sheet-drag-indicator behavior) plus sheet sizing.
/// No navigation title/toolbar/Done button: `MetricDetailView` shows the metric's own name inline
/// above its value instead, and dismissal is the standard swipe-down gesture every sheet gets for
/// free, matching `ActivityDetailView`'s own precedent. Opened by tapping a metric's own pill in
/// the day list. All the actual content lives in `MetricDetailView`, kept separate so a future
/// dashboard screen can embed that content directly without this sheet-specific chrome.
struct FitnessMetricsInfoView: View {
    let kind: TrainingMetricKind
    let chartContext: MetricChartContext
    /// The selected chart period, owned by `WeekView` so it's retained across separate metric
    /// sheets rather than resetting every time a different pill is tapped.
    @Binding var period: ChartPeriod
    let metricsProvider: (ClosedRange<Date>) async -> [FitnessMetrics]

    var body: some View {
        NavigationStack {
            MetricDetailView(kind: kind, chartContext: chartContext, period: $period, metricsProvider: metricsProvider)
        }
        // The content doesn't need the full screen, but does need more than a sliver -- `.medium`
        // as the default with `.large` still reachable by dragging, for a long Form explanation
        // (chart + legend + zone card + About card) on a small phone.
        .presentationDetents([.medium, .large])
    }
}
