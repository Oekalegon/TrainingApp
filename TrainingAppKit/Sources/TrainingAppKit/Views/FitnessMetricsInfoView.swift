import SwiftUI
import TrainingCore

/// A sheet explaining one fitness metric — Load, Fitness (CTL), Fatigue (ATL), or Form (TSB) —
/// opened by tapping that metric's own pill in the day list (MVP1-45): its own trend chart, plain
/// explanation, and (Form only) its current zone. Purely informational: no state of its own, no
/// actions besides dismissal.
struct FitnessMetricsInfoView: View {
    /// What `kind`'s own detail chart needs.
    struct ChartContext {
        /// The 3-week window `WeekViewModel.chartMetrics(for:)` returns for the week containing
        /// `touchedDay` — the same data `FitnessChartView`/`DailyLoadChartView` plot for the main
        /// week graph, so the numbers agree between the two places they're shown.
        let metrics: [FitnessMetrics]
        let displayedWeekRange: ClosedRange<Date>
        /// The specific day whose pill was tapped — highlighted in the chart, and (for Form) whose
        /// own value the "current zone" explanation below its chart is read from.
        let touchedDay: Date
        /// The athlete's own calendar — matching `touchedDay` against `metrics` needs
        /// `calendar.isDate(_:inSameDayAs:)`, not `==`, the same reasoning
        /// `WeekViewModel.metrics(on:)` already documents for the same comparison.
        let calendar: Calendar
    }

    let kind: TrainingMetricKind
    let chartContext: ChartContext
    @Environment(\.dismiss) private var dismiss

    /// `chartContext.touchedDay`'s own metrics point, for Form's "current zone" explanation —
    /// `nil` if that day isn't in `chartContext.metrics` yet (not loaded).
    private var touchedMetrics: FitnessMetrics? {
        chartContext.metrics.first {
            chartContext.calendar.isDate($0.day, inSameDayAs: chartContext.touchedDay)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    detailChart
                        .listRowInsets(EdgeInsets())
                        .padding(.vertical, 8)
                    if kind == .form, let touchedMetrics {
                        formZoneExplanation(for: touchedMetrics)
                    }
                    Text(kind.explanation)
                        .foregroundStyle(.secondary)
                } header: {
                    // Plain, un-tinted icon+name — matching the day list's own pills
                    // (`MetricPillView`'s doc comment), which deliberately don't tint the icon per
                    // metric either: the icon shape and the name right next to it already
                    // disambiguate the four without needing a color association.
                    Label("\(kind.name) (\(kind.abbreviation))", systemImage: kind.icon)
                        // The header's own default styling already renders it as a small caption;
                        // without this the icon+name reads at that same tiny size instead of
                        // standing out as this section's own title.
                        .font(.headline)
                }
            }
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
        // One metric's chart+explanation doesn't need the full screen, but does need more than a
        // sliver -- `.medium` as the default with `.large` still reachable by dragging, for a long
        // Form explanation (chart + legend + current zone + paragraph) on a small phone.
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var detailChart: some View {
        switch kind {
        case .load:
            LoadDetailChartView(
                metrics: chartContext.metrics,
                displayedWeekRange: chartContext.displayedWeekRange,
                touchedDay: chartContext.touchedDay,
                calendar: chartContext.calendar
            )
        case .fitness, .fatigue, .form:
            FitnessTrendDetailChartView(
                metrics: chartContext.metrics,
                displayedWeekRange: chartContext.displayedWeekRange,
                emphasized: kind
            )
        }
    }

    /// Deliberately plain (bold text, no zone color) — matching this sheet's own header, which
    /// stays un-tinted even though the chart above (and the main week graph) shade this same zone
    /// in color; the color association lives in the chart, not repeated here in text.
    private func formZoneExplanation(for metrics: FitnessMetrics) -> some View {
        let zone = metrics.tsbZone()
        return VStack(alignment: .leading, spacing: 4) {
            Text("Currently: \(zone.label)")
                .font(.subheadline.bold())
            Text(zone.explanation)
                .foregroundStyle(.secondary)
        }
    }
}
