import SwiftUI
import TrainingCore

/// The "Time in Zone" graph panel's own detail screen (MVP1-60) — pushed the same way
/// `MetricDetailView` is (`WeekView`'s `NavigationStack`, a graph-panel tap), reusing its Apple
/// Health-style visual language (a caption/value/date header, white band with the chart, grouped
/// cards below) even though a heart-rate histogram doesn't fit `MetricDetailView` itself: it's a
/// distribution across the displayed week, not one metric with a single day's or week's own value.
/// The white band's own chart is a two-page carousel (MVP1-76 follow-up): the continuous bpm
/// histogram, then `HeartRateZoneBarChartView`'s bar-per-zone breakdown — the same "one card, page
/// between related charts" treatment `GraphPanelPagerView` uses for the week view's own graph
/// panel. `valueHeader` follows whichever page is showing (`selectedChartIndex`): the histogram's
/// own 80th-percentile heart rate for page 0, or the week's overall Low-Intensity-Training fraction
/// (Seiler's 80/20 model) for page 1 — each page's headline number is the one that page's own
/// chart is actually about, rather than one fixed value regardless of which chart is on screen.
/// Below that: `timeInZoneSection` — each zone's own name+explanation, in one card — then
/// `aboutSection`'s general explanation of what zones are, in that order (the specific "what
/// happened this week" reading before the general "what zones are" background).
struct HeartRateZoneDetailView: View {
    let histogram: HeartRateHistogram
    /// `WeekViewModel.displayedWeekDateRangeDescription` — this panel is only ever reachable by
    /// tapping the *current* page, so it's always the displayed week already, not the page's own
    /// (possibly different) week the way `MetricChartContext` has to account for.
    let weekDateRangeText: String
    /// Which of `chartCard`'s two pages (histogram, then the zone bar chart) is showing — a plain
    /// `@State` rather than `GraphPanelPagerView`'s hand-rolled drag gesture, since this screen has
    /// no competing horizontal gesture to avoid (it sits in a vertical-only `ScrollView`, not
    /// alongside `WeekView`'s own week-swipe), so `TabView(.page)` works here without the gesture
    /// conflict that ruled it out there.
    @State private var selectedChartIndex: Int = 0
    private static let chartPageCount = 2

    /// The 80th-percentile heart rate, `nil` when the week has no in-zone time recorded at all
    /// (the same condition `HeartRateHistogramChartView.hasAnyTime` checks, via the same call).
    private var eightyPercentileBPM: Double? {
        histogram.percentileBPM(0.8)
    }

    private var percentileValueText: String {
        guard let eightyPercentileBPM else { return "–" }
        return "\(Int(eightyPercentileBPM.rounded()))"
    }

    private var lowIntensityValueText: String {
        guard let fraction = histogram.lowIntensityFraction else { return "–" }
        return fraction.formatted(.percent.precision(.fractionLength(0)))
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
    /// ever has one "kind" of value at a time), the value itself, then the week's own date range
    /// underneath. Follows `selectedChartIndex` (MVP1-76 follow-up) rather than showing one fixed
    /// value regardless of which chart page is on screen: the percentile/bpm reading belongs to
    /// the histogram page, and the LIT fraction belongs to the zone-bar page, so showing either
    /// one while the other chart is visible would read as unrelated to what's actually on screen.
    /// The LIT caption spells out "Low Intensity Training" rather than just "LIT" so the
    /// abbreviation used everywhere else it's shown (`SportStatsPagerView`'s own per-sport tile,
    /// `ActivityDetailView`) has a place in the app where a reader can see what it stands for.
    @ViewBuilder
    private var valueHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            if selectedChartIndex == 0 {
                Text("80th Percentile Heart Rate")
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
            } else {
                Text("Low Intensity Training (LIT)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(lowIntensityValueText)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
            }
            Text(weekDateRangeText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Same 172pt plot height both pages already share (MVP1-55/MVP1-77) — the user asked not to
    /// grow this further, just to tighten the space around it. (A previous `.frame(height: 260)`
    /// here didn't actually enlarge the plot, which is fixed at 172pt inside
    /// `HeartRateHistogramChartView`/`HeartRateZoneBarChartView` themselves — it just centered that
    /// same content in 88pt of dead space, which is what actually needed fixing.) `showsCaption:
    /// false` drops the histogram's own "Heart Rate Histogram" caption — redundant here, with
    /// `valueHeader` right above it and "Time in Zone" already the nav title — matching how
    /// `MetricDetailView`'s own detail charts carry no such caption either. Page dots use the same
    /// 5pt/`.primary`-vs-25%-opacity styling `GraphPanelPagerView`'s own page dots do, so paging
    /// reads the same way in both places (`.tabViewStyle`'s own dots are hidden in favor of these,
    /// for that same visual-consistency reason).
    private var chartCard: some View {
        VStack(spacing: 8) {
            TabView(selection: $selectedChartIndex) {
                HeartRateHistogramChartView(histogram: histogram, showsCaption: false)
                    .tag(0)
                HeartRateZoneBarChartView(histogram: histogram)
                    .tag(1)
            }
            // `.page` (with its own dots hidden, in favor of the matching row built below) isn't
            // available in the macOS build `swift test` runs this package under -- only the app
            // target itself is iOS-only. macOS keeps `TabView`'s own default style; the `$selectedChartIndex`
            // binding still pages correctly there, just without swipe gestures.
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
            #endif
            .frame(height: 172)
            HStack(spacing: 4) {
                ForEach(0..<Self.chartPageCount, id: \.self) { index in
                    Circle()
                        .fill(index == selectedChartIndex ? Color.primary : Color.primary.opacity(0.25))
                        .frame(width: 5, height: 5)
                }
            }
            .accessibilityHidden(true)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(metricDetailChartCardBackground)
    }

    /// Each zone's own name+explanation (MVP1-77) — the bar chart that used to live inside this
    /// same card now pages alongside the histogram in `chartCard` instead (MVP1-76 follow-up), so
    /// this section is just the row list, matching `MetricDetailView.formZoneSection`'s own shape
    /// (a title above a rounded card of rows, no embedded chart) rather than carrying a chart of
    /// its own. Row layout/dividers match that same section (MVP1-75/MVP1-79), minus its "current
    /// zone" row highlight — unlike Form, there's no single zone a whole week's worth of heart-rate
    /// data is "currently in", so `zoneRow` doesn't try to pick one out.
    private var timeInZoneSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Time in Zone")
                .font(.title3.weight(.bold))
                .padding(.horizontal)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(HeartRateZone.allCases, id: \.self) { zone in
                    if zone != HeartRateZone.allCases.first {
                        Divider()
                    }
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
