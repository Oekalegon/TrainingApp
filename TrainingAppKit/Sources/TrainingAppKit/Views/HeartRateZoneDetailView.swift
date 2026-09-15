import SwiftUI
import TrainingCore

/// The "Time in Zone" graph panel's own detail screen (MVP1-60) — pushed the same way
/// `MetricDetailView` is (`WeekView`'s `NavigationStack`, a graph-panel tap), reusing its Apple
/// Health-style visual language (a caption/value/date header, white band with the chart, grouped
/// "About" cards below) even though a heart-rate histogram doesn't fit `MetricDetailView` itself:
/// it's a distribution across the displayed week, not one metric with a single day's or week's own
/// value. The one number worth surfacing as this screen's own "value" is the 80th-percentile heart
/// rate (Seiler's 80/20 polarized-training threshold, the same one `HeartRateHistogramChartView`
/// marks on the chart itself) — everything else about the distribution is what the chart is for.
struct HeartRateZoneDetailView: View {
    let histogram: HeartRateHistogram
    /// `WeekViewModel.displayedWeekDateRangeDescription` — this panel is only ever reachable by
    /// tapping the *current* page, so it's always the displayed week already, not the page's own
    /// (possibly different) week the way `MetricChartContext` has to account for.
    let weekDateRangeText: String

    /// The 80th-percentile heart rate, `nil` when the week has no in-zone time recorded at all
    /// (the same condition `HeartRateHistogramChartView.hasAnyTime` checks, via the same call).
    private var eightyPercentileBPM: Double? {
        histogram.percentileBPM(0.8)
    }

    private var percentileValueText: String {
        guard let eightyPercentileBPM else { return "–" }
        return "\(Int(eightyPercentileBPM.rounded()))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Same "white above, grouped cards below" split as `MetricDetailView` — see that
                // type's own doc comment.
                VStack(alignment: .leading, spacing: 20) {
                    valueHeader
                        .padding(.horizontal)
                        .padding(.top)
                    chartCard
                }
                .background(metricDetailChartCardBackground)
                aboutSection
                    .padding(.horizontal)
                    .padding(.vertical)
            }
        }
        .background(metricDetailBackground)
        .navigationTitle("Time in Zone")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(metricDetailChartCardBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        #endif
    }

    /// Same layout as `MetricDetailView.valueHeader`: a caption above the value (here always shown,
    /// not conditional on a `.week`-vs-`.day` subject the way that one is, since this screen only
    /// ever has one "kind" of value), the value itself with its own "bpm" unit, then the week's own
    /// date range underneath.
    private var valueHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("80% Percentile Heart Rate")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(percentileValueText)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                if eightyPercentileBPM != nil {
                    Text("bpm")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Text(weekDateRangeText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Taller than the graph panel's own 172pt (MVP1-55) — this screen has nothing else competing
    /// for vertical space, so the chart can use the room a detail view affords it.
    private var chartCard: some View {
        HeartRateHistogramChartView(histogram: histogram)
            .frame(height: 260)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(metricDetailChartCardBackground)
    }

    /// One "About Heart Rate Zones" card listing all five zones — a single card, not one per zone
    /// (unlike `MetricDetailView`'s own Form-zone/About cards): each zone's own explanation is a
    /// sentence, not a paragraph, so five short rows read better as one grouped list than as five
    /// separate cards competing for the same "About" treatment.
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About Heart Rate Zones")
                .font(.title3.weight(.bold))
                .padding(.horizontal)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(HeartRateZone.allCases, id: \.self) { zone in
                    zoneRow(zone)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(metricDetailAboutCardBackground)
            }
        }
    }

    private func zoneRow(_ zone: HeartRateZone) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(zone.color)
                .frame(width: 10, height: 10)
                // Nudges the dot to align with the first line's cap-height, not the row's own top.
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text("Zone \(zone.rawValue) · \(zone.displayName)")
                    .font(.subheadline.weight(.semibold))
                Text(zone.explanation)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
        }
    }
}
