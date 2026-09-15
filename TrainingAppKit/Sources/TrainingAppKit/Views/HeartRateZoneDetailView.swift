import SwiftUI
import TrainingCore

/// The "Time in Zone" graph panel's own detail screen (MVP1-60) — pushed the same way
/// `MetricDetailView` is (`WeekView`'s `NavigationStack`, a graph-panel tap), reusing its Apple
/// Health-style visual language (white band with the chart, grouped "About" cards below) even
/// though the underlying data doesn't fit `MetricDetailView` itself: a heart-rate histogram is a
/// distribution across the displayed week, not one metric with a single day's or week's own value,
/// so there's no big-number header here — just the week's own date range, the same
/// `HeartRateHistogramChartView` the graph panel itself shows (just given more room), and one card
/// per zone explaining what it means.
struct HeartRateZoneDetailView: View {
    let histogram: HeartRateHistogram
    /// `WeekViewModel.displayedWeekDateRangeDescription` — this panel is only ever reachable by
    /// tapping the *current* page, so it's always the displayed week already, not the page's own
    /// (possibly different) week the way `MetricChartContext` has to account for.
    let weekDateRangeText: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Same "white above, grouped cards below" split as `MetricDetailView` — see that
                // type's own doc comment.
                VStack(alignment: .leading, spacing: 12) {
                    Text(weekDateRangeText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
