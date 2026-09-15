import SwiftUI

/// The sheet chrome around `MetricDetailView` (MVP1-45) — a `NavigationStack` with a title and
/// "Done" button, plus sheet sizing. Opened by tapping a metric's own pill in the day list. All
/// the actual content lives in `MetricDetailView`, kept separate so a future dashboard screen can
/// embed that content directly without this sheet-specific chrome.
struct FitnessMetricsInfoView: View {
    let kind: TrainingMetricKind
    let chartContext: MetricChartContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MetricDetailView(kind: kind, chartContext: chartContext)
                .navigationTitle("\(kind.name) (\(kind.abbreviation))")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
        // The content doesn't need the full screen, but does need more than a sliver -- `.medium`
        // as the default with `.large` still reachable by dragging, for a long Form explanation
        // (chart + legend + current zone + paragraph) on a small phone.
        .presentationDetents([.medium, .large])
    }
}
