import Charts
import SwiftUI
import TrainingCore

/// A second chart on the "Time in Zone" info page (MVP1-77), alongside
/// `HeartRateHistogramChartView`'s smoothed bpm line: one horizontal bar per zone, its length the
/// displayed week's share of in-zone time spent in that zone — a coarser, easier-to-read-at-a-
/// glance summary of the same underlying histogram, in the same zone order (Z1 top, Z5 bottom) as
/// the zone rows listed alongside it. Deliberately axis/grid-free: each bar carries its own
/// "Z1 · 5%"-style label as a trailing annotation, so the plain bar lengths are the whole point
/// rather than something to cross-reference against a scale. A zone with no recorded time still
/// draws a hairline in its own color (``barLength(_:domainUpperBound:chartWidth:)``) rather than
/// disappearing, so all five zones stay visible even in a week that never reached one.
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
                Text("\(entry.zone.shortLabel) · \(Self.percentageText(entry.minutes, of: total))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .chartXScale(domain: 0...domainUpperBound)
        // Z1 top, Z5 bottom -- the first domain entry renders at the top of a horizontal bar
        // chart's categorical axis, so this needs the reverse of `HeartRateZone.allCases`' own
        // (ascending) order.
        .chartYScale(domain: HeartRateZone.allCases.map(\.shortLabel).reversed())
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        // Measures the plot area itself (not this view's own outer width, which would also count
        // the space `Chart` reserves for each bar's trailing annotation) so
        // `barLength(_:domainUpperBound:chartWidth:)`'s width-to-value conversion is accurate
        // rather than an overestimate — same
        // `proxy.plotFrame` idiom `HeartRateHistogramChartView`'s own overlay uses to place its
        // zone-band labels.
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    Color.clear
                        .onAppear { chartWidth = geometry[plotFrame].width }
                        .onChange(of: geometry[plotFrame].width) { _, newValue in chartWidth = newValue }
                }
            }
        }
    }

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
