import Charts
import SwiftUI
import TrainingCore

/// A second chart on the "Time in Zone" info page (MVP1-76/MVP1-77), paging alongside
/// `HeartRateHistogramChartView`'s smoothed bpm line: one horizontal bar per zone, its length the
/// displayed week's share of in-zone time spent in that zone — a coarser, easier-to-read-at-a-
/// glance summary of the same underlying histogram, in the same zone order (Z1 top, Z5 bottom) as
/// the zone rows listed alongside it. A manually-drawn leading label names each row's own zone
/// (Z1–Z5, see `chartOverlay`'s own doc comment for why that's manual rather than a native
/// `chartYAxis`); a bottom axis grids the minutes scale each bar is measured against, the same
/// gridline/tick/label treatment `HeartRateHistogramChartView`'s own x-axis uses, plus a solid
/// baseline along the plot's bottom edge. Each bar still carries its own percentage as a trailing
/// annotation (just the share, not the zone label, now that the leading label already names it). A
/// zone with no recorded time still draws a hairline in its own color
/// (``barLength(_:domainUpperBound:chartWidth:)``) rather than disappearing, so all five zones stay
/// visible even in a week that never reached one.
struct HeartRateZoneBarChartView: View {
    let histogram: HeartRateHistogram

    /// The chart's own *plot* width in points — its bars' actual drawable span, narrower than the
    /// view's own width by whatever `Chart` reserves for each bar's trailing annotation text — so
    /// ``barLength(_:domainUpperBound:chartWidth:)`` can turn ``zeroBarPixelWidth`` into a plotted value
    /// that renders as close to that many points wide as this two-pass (`chartOverlay` reports the
    /// real size one frame after the first render, same lag `MetricDetailView.panState.chartWidth`
    /// already has) measurement allows. The `300` default is only ever visible for that first
    /// frame, before `chartOverlay` reports the real value.
    @State private var chartWidth: CGFloat = 300

    private var minutesByZone: [(zone: HeartRateZone, minutes: Double)]? {
        histogram.minutesByZone()
    }

    private var hasAnyTime: Bool {
        minutesByZone?.contains { $0.minutes > 0 } ?? false
    }

    var body: some View {
        Group {
            if hasAnyTime, let minutesByZone {
                chart(minutesByZone)
            } else {
                ContentUnavailableView(
                    "No Heart-Rate Data",
                    systemImage: "heart.slash",
                    description: Text("No heart-rate zones recorded this week.")
                )
            }
        }
        .frame(height: 172)
        .padding(.horizontal)
    }

    private func chart(_ minutesByZone: [(zone: HeartRateZone, minutes: Double)]) -> some View {
        let total = minutesByZone.reduce(0) { $0 + $1.minutes }
        let maxMinutes = minutesByZone.map(\.minutes).max() ?? 0
        let domainUpperBound = Self.domainUpperBound(forMaxMinutes: maxMinutes)
        return Chart(minutesByZone, id: \.zone) { entry in
            BarMark(
                x: .value(
                    "Minutes",
                    Self.barLength(entry.minutes, domainUpperBound: domainUpperBound, chartWidth: chartWidth)
                ),
                y: .value("Zone", entry.zone.shortLabel)
            )
            .foregroundStyle(entry.zone.color)
            .annotation(position: .trailing) {
                Text(Self.percentageText(entry.minutes, of: total))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .chartXScale(domain: 0...domainUpperBound)
        // Z1 top, Z5 bottom -- the first domain entry renders at the top of a horizontal bar
        // chart's categorical axis, so this needs the reverse of `HeartRateZone.allCases`' own
        // (ascending) order.
        .chartYScale(domain: HeartRateZone.allCases.map(\.shortLabel).reversed())
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisTick()
                if let minutes = value.as(Double.self) {
                    AxisValueLabel("\(Int(minutes.rounded()))m")
                }
            }
        }
        // Hidden, not `position: .leading`: a plain categorical `chartYAxis` doesn't reliably
        // reserve real margin to its left in this chart (no numeric y-values to measure a width
        // from), so its labels ended up drawn *inside* the plot area, overlapping each bar's own
        // leading edge instead of sitting beside it. `Self.leadingLabelWidth`'s own fixed padding
        // below, plus the manual `Text` per zone in `chartOverlay`, guarantees real, un-overlapped
        // space instead.
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .padding(.leading, Self.leadingLabelWidth)
        // Measures the plot area itself (not this view's own outer width, which would also count
        // the space `Chart` reserves for each bar's trailing annotation) so
        // `barLength(_:domainUpperBound:chartWidth:)`'s width-to-value conversion is accurate
        // rather than an overestimate — same `proxy.plotFrame` idiom
        // `HeartRateHistogramChartView`'s own overlay uses to place its zone-band labels. Also
        // draws, in the `Self.leadingLabelWidth` margin `.padding(.leading)` reserved above: each
        // zone's own label, vertically centered on its own row (`proxy.position(forY:)`, the same
        // idiom `FitnessTrendDetailChartView`'s zone-band-name overlay in `MetricDetailChartView`
        // uses); and a solid baseline along the plot's bottom edge marking the x-axis itself, since
        // `AxisGridLine()` above only draws gridlines at each tick, not a continuous axis line.
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let plotArea = geometry[plotFrame]
                    Color.clear
                        .onAppear { chartWidth = plotArea.width }
                        .onChange(of: plotArea.width) { _, newValue in chartWidth = newValue }
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: plotArea.width, height: 1)
                        .position(x: plotArea.midX, y: plotArea.maxY)
                    ForEach(HeartRateZone.allCases, id: \.self) { zone in
                        if let y = proxy.position(forY: zone.shortLabel) {
                            Text(zone.shortLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: Self.leadingLabelWidth - 6, alignment: .trailing)
                                .position(x: plotArea.minX - Self.leadingLabelWidth / 2, y: plotArea.minY + y)
                        }
                    }
                }
            }
        }
    }

    /// Fixed leading margin reserved (via `.padding(.leading)`) for each zone's own label —
    /// `chartYAxis(.hidden)`'s own doc comment explains why this is manual rather than relying on
    /// the native axis to reserve it. Wide enough for "Z1"–"Z5" at `.caption2` with a little
    /// breathing room before the plot's own leading edge.
    private static let leadingLabelWidth: CGFloat = 24

    /// How wide a zero-minute zone's bar renders, regardless of the data's own scale.
    private static let zeroBarPixelWidth: CGFloat = 1

    /// Extra domain headroom past the longest bar's own value, as a multiple of that value --
    /// reserves room for that bar's own trailing annotation (a short "Z2 · 63%"-style label) so it
    /// never has to draw past the chart's plot bounds (MVP1-78 follow-up).
    private static let annotationHeadroomMultiplier: Double = 1.3

    /// `chartXScale`'s domain upper bound, padded past `maxMinutes` (the longest bar's own value —
    /// `0` if every zone is empty) by ``annotationHeadroomMultiplier`` — see that constant's own
    /// doc comment for why the padding exists. `internal`, not `private`, so it's directly
    /// unit-testable via `@testable import` rather than only indirectly through rendered output.
    static func domainUpperBound(forMaxMinutes maxMinutes: Double) -> Double {
        max(maxMinutes, 1) * annotationHeadroomMultiplier
    }

    /// `entry.minutes`, unless that's 0 -- then whatever value plots as exactly
    /// ``zeroBarPixelWidth`` points wide given `chartXScale`'s `0...domainUpperBound` domain
    /// mapped across `chartWidth` points, so every zone still draws a colored mark rather than
    /// vanishing entirely. Purely visual: `percentageText(_:of:)` still reports the real (0%)
    /// share, computed from `entry.minutes` itself, not this padded value. `internal`, not
    /// `private`, so it's directly unit-testable via `@testable import`.
    static func barLength(_ minutes: Double, domainUpperBound: Double, chartWidth: CGFloat) -> Double {
        guard minutes <= 0 else { return minutes }
        guard chartWidth > 0 else { return 0 }
        return domainUpperBound * Double(zeroBarPixelWidth / chartWidth)
    }

    private static func percentageText(_ minutes: Double, of total: Double) -> String {
        guard total > 0 else { return "0%" }
        return "\(Int((minutes / total * 100).rounded()))%"
    }
}
