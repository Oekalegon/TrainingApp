import SwiftUI
import TrainingCore

/// The "Time in Zone" graph panel's own detail screen (MVP1-60) — pushed the same way
/// `MetricDetailView` is (`WeekView`'s `NavigationStack`, a graph-panel tap), reusing its Apple
/// Health-style visual language (a caption/value/date header, white band with the chart, grouped
/// cards below) even though a heart-rate histogram doesn't fit `MetricDetailView` itself: it's a
/// distribution across the displayed week, not one metric with a single day's or week's own value.
/// The one number worth surfacing as this screen's own "value" is the 80th-percentile heart rate
/// (Seiler's 80/20 polarized-training threshold, the same one `HeartRateHistogramChartView` marks
/// on the chart itself). Below the white band: `timeInZoneSection` (MVP1-77) — the bar-per-zone
/// breakdown alongside each zone's own description, in one card — then `aboutSection`'s general
/// explanation of what zones are, in that order (the specific "what happened this week" reading
/// before the general "what zones are" background).
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

    /// The gap between the value header and the chart, right above it in the same white band —
    /// tighter than ``sectionSpacing`` below, since a caption and its own chart read as one unit
    /// rather than two separate things.
    private static let headerToChartSpacing: CGFloat = 12

    /// The gap between every distinct section below the white band: chart → `timeInZoneSection`,
    /// and `timeInZoneSection` → `aboutSection`. One value for both, so the chart's own section
    /// break reads exactly as prominent as the break between the two cards after it, not a
    /// smaller gap that reads as still-part-of-the-chart.
    private static let sectionSpacing: CGFloat = 40

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Same "white above, grouped cards below" split as `MetricDetailView` — see that
                // type's own doc comment.
                VStack(alignment: .leading, spacing: Self.headerToChartSpacing) {
                    valueHeader
                        .padding(.horizontal)
                        .padding(.top)
                    chartCard
                }
                .background(metricDetailChartCardBackground)
                timeInZoneSection
                    .padding(.horizontal)
                    .padding(.top, Self.sectionSpacing)
                aboutSection
                    .padding(.horizontal)
                    .padding(.top, Self.sectionSpacing)
                    .padding(.bottom, Self.sectionSpacing)
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

    /// Same 172pt plot height as the graph panel's own (MVP1-55) — the user asked not to grow this
    /// further, just to tighten the space around it. (A previous `.frame(height: 260)` here didn't
    /// actually enlarge the plot, which is fixed at 172pt inside `HeartRateHistogramChartView`
    /// itself — it just centered that same content in 88pt of dead space, which is what actually
    /// needed fixing.) `showsCaption: false` drops that view's own "Heart Rate Histogram" caption —
    /// redundant here, with `valueHeader` right above it and "Time in Zone" already the nav title —
    /// matching how `MetricDetailView`'s own detail charts carry no such caption either.
    private var chartCard: some View {
        HeartRateHistogramChartView(histogram: histogram, showsCaption: false)
            .frame(maxWidth: .infinity)
            .background(metricDetailChartCardBackground)
    }

    /// A second chart (MVP1-77) below `chartCard`'s bpm line: a horizontal bar per zone, its
    /// share of the displayed week's in-zone time — paired here with per-zone description rows
    /// (moved down from `aboutSection`, which used to be just this list) in one card, so the bars
    /// and the zone they each belong to read as one explained thing rather than two disconnected
    /// sections. `HeartRateZoneBarChartView`'s own doc comment explains why this chart exists
    /// alongside the histogram rather than replacing it. Row layout/dividers match
    /// `MetricDetailView.formZoneSection` (MVP1-75/MVP1-79), minus that section's own "current
    /// zone" row highlight — unlike Form, there's no single zone a whole week's worth of heart-rate
    /// data is "currently in", so `zoneRow` doesn't try to pick one out.
    private var timeInZoneSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Time in Zone")
                .font(.title3.weight(.bold))
                .padding(.horizontal)
            VStack(alignment: .leading, spacing: 0) {
                HeartRateZoneBarChartView(histogram: histogram)
                    .padding()
                ForEach(HeartRateZone.allCases, id: \.self) { zone in
                    Divider()
                    zoneRow(zone)
                }
            }
            .background(metricDetailAboutCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    /// General "About Heart Rate Zones" text (MVP1-77) — unlike `timeInZoneSection`'s own per-zone
    /// rows (this week's actual zones, each already named and colored), this is just what zones
    /// *are* and why the split across them matters, once, in prose rather than a fifth repetition
    /// of the same five names/colors already shown twice above.
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About Heart Rate Zones")
                .font(.title3.weight(.bold))
                .padding(.horizontal)
            Text(Self.aboutHeartRateZonesText)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(metricDetailAboutCardBackground)
                }
        }
    }

    private static let aboutHeartRateZonesText: String =
        "Heart-rate zones split effort into five bands, from easy recovery to maximal exertion, "
            + "each training a different part of your fitness. Most endurance training happens in "
            + "the easier zones, with only a small share spent hard — Seiler's 80/20 polarized "
            + "approach, the split the histogram above marks at its 80th-percentile line."

    /// One `HeartRateZone`'s row in `timeInZoneSection` — `ZoneListRow`, with no `highlightTint`
    /// (leaves it `nil`): see `timeInZoneSection`'s own doc comment for why there's no "current
    /// zone" here the way there is for Form.
    private func zoneRow(_ zone: HeartRateZone) -> some View {
        ZoneListRow(color: zone.color, title: "Zone \(zone.rawValue) · \(zone.displayName)", explanation: zone.explanation)
    }
}
