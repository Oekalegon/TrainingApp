import SwiftUI
import TrainingCore

/// A sheet explaining one or all of the four fitness metrics shown throughout the week view —
/// Load, Fitness (CTL), Fatigue (ATL), and Form (TSB) (MVP1-45). Tapping a specific pill in the
/// day list opens just that metric's own explanation plus its own trend chart (`focusedKind` and
/// `chartContext` both set); the toolbar's general "Fitness Metrics" entry point opens all four,
/// text-only (both `nil`). Purely informational: no state of its own, no actions besides
/// dismissal.
struct FitnessMetricsInfoView: View {
    /// What `focusedKind`'s own detail chart needs — the toolbar's all-four case has no chart at
    /// all, so this is only ever set alongside a non-`nil` `focusedKind`.
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

    /// The one metric to explain, or `nil` to list all four — see this type's own doc comment.
    var focusedKind: TrainingMetricKind?
    var chartContext: ChartContext?
    @Environment(\.dismiss) private var dismiss

    private var kinds: [TrainingMetricKind] {
        focusedKind.map { [$0] } ?? TrainingMetricKind.allCases
    }

    /// `chartContext.touchedDay`'s own metrics point, for Form's "current zone" explanation —
    /// `nil` if that day isn't in `chartContext.metrics` yet (not loaded) or there's no chart
    /// context at all (the toolbar's all-four case).
    private var touchedMetrics: FitnessMetrics? {
        guard let chartContext else { return nil }
        return chartContext.metrics.first {
            chartContext.calendar.isDate($0.day, inSameDayAs: chartContext.touchedDay)
        }
    }

    var body: some View {
        NavigationStack {
            List(kinds, id: \.self) { kind in
                Section {
                    if let chartContext, kind == focusedKind {
                        detailChart(for: kind, context: chartContext)
                            .listRowInsets(EdgeInsets())
                            .padding(.vertical, 8)
                        if kind == .form, let touchedMetrics {
                            formZoneExplanation(for: touchedMetrics)
                        }
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
                        // standing out as each section's own title.
                        .font(.headline)
                }
            }
            // "Load", not "Fitness Metrics", when this is one metric's own sheet -- the plural
            // title only fits the all-four case.
            .navigationTitle(focusedKind.map { "\($0.name) (\($0.abbreviation))" } ?? "Fitness Metrics")
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
        // A single metric's chart+explanation doesn't need the full screen, but does need more
        // than a sliver -- `.medium` as the default with `.large` still reachable by dragging, for
        // a long Form explanation (chart + legend + current zone + paragraph) on a small phone.
        .presentationDetents(focusedKind != nil ? [.medium, .large] : [.large])
    }

    @ViewBuilder
    private func detailChart(for kind: TrainingMetricKind, context: ChartContext) -> some View {
        switch kind {
        case .load:
            LoadDetailChartView(
                metrics: context.metrics,
                displayedWeekRange: context.displayedWeekRange,
                touchedDay: context.touchedDay,
                calendar: context.calendar
            )
        case .fitness, .fatigue, .form:
            FitnessTrendDetailChartView(
                metrics: context.metrics,
                displayedWeekRange: context.displayedWeekRange,
                emphasized: kind
            )
        }
    }

    /// Deliberately plain (bold text, no zone color) — matching this sheet's own headers, which
    /// stay un-tinted even though the chart above (and the main week graph) shade this same zone
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
