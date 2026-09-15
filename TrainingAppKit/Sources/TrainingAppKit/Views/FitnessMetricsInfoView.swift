import SwiftUI

/// The sheet chrome around `MetricDetailView` (MVP1-45) — just sheet sizing. Opened by tapping a
/// metric's own pill in the day list. No navigation title/toolbar/Done button: `MetricDetailView`
/// shows the metric's own name inline above its value instead, and dismissal is the standard
/// swipe-down gesture every sheet gets for free, matching `ActivityDetailView`'s own precedent.
/// All the actual content lives in `MetricDetailView`, kept separate so a future dashboard screen
/// can embed that content directly without this sheet-specific chrome.
struct FitnessMetricsInfoView: View {
    let kind: TrainingMetricKind
    let chartContext: MetricChartContext

    var body: some View {
        MetricDetailView(kind: kind, chartContext: chartContext)
            // The content doesn't need the full screen, but does need more than a sliver --
            // `.medium` as the default with `.large` still reachable by dragging, for a long Form
            // explanation (chart + legend + zone explanation + About card) on a small phone.
            .presentationDetents([.medium, .large])
    }
}
