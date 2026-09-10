import Charts
import SwiftUI
import TrainingCore

/// The week view's graph panel "Time in zone" page (MVP1-55, design doc §2.1; histogram follow-up)
/// — a heart-rate histogram of the displayed week's activities, binned every 5 bpm, plotted over
/// muted background bands for each heart-rate zone (same visual language `FitnessChartView` uses
/// for TSB zones) with a single smoothed line tracing the time spent at each bpm, and a light-gray
/// rule (labeled with an "80" pill) at the 80th percentile (Seiler's 80/20 polarized-training
/// threshold).
///
/// Deliberately scoped to just the displayed week, not the 3-week window `FitnessChartView`/
/// `DailyLoadChartView` share: unlike load/CTL/ATL/TSB (already computed for the whole
/// `chartRange` by `TrainingModel.recompute`), the histogram here is built from raw samples —
/// see `WeekViewModel.heartRateHistogram`'s own doc comment for why that's computed
/// asynchronously off the main actor rather than synchronously here — and widening the window to
/// 21 days would triple the cost of every recomputation.
///
/// A thin grey line per activity (underneath this combined one) was tried here too, for spotting
/// individual sessions' distributions against the week's aggregate — removed for now (not the
/// underlying data pipeline, just this view's use of it) after it was identified as the source of
/// choppy panning/swiping on weeks with several activities, and hiding it only during the
/// week-change slide wasn't enough to fix that on its own.
struct TimeInZoneChartView: View {
    let histogram: HeartRateHistogram

    private static let smoothedLineWidth: CGFloat = 3
    /// Thinner than `smoothedLineWidth` and drawn before it in `chart` (so it sits behind), per
    /// the 80/20 polarized-training threshold's supporting role — it marks a reference point on
    /// the histogram, not a second series competing with it.
    private static let percentileLineWidth: CGFloat = 1
    /// Padding (in bpm) added below zone 1's lower bound and above zone 5's upper bound — the
    /// histogram is deliberately scoped to the zones themselves (design intent: this is a "time in
    /// zone" chart, not a general heart-rate distribution), not widened to fit whatever the actual
    /// recorded data happens to span. Also doubles as the density-filled runway
    /// `.interpolationMethod(.catmullRom)` needs to visibly decay to zero before the domain's own
    /// edge, rather than still reading as a non-zero value right at the boundary: a spline fit
    /// through the zero-filled points beyond the real data (see `densifiedMinutesByBPM`) needs
    /// several of them to flatten out before the edge is reached, and at the default 5bpm bin
    /// width this gives it three.
    private static let domainPadding: Double = 15
    /// Domain used when the athlete has no resolvable heart-rate zones at all (so there's no
    /// zone-boundary-based domain to fall back to) and the histogram itself has no bins yet.
    private static let fallbackDomain: ClosedRange<Double> = 60...200

    private struct ZoneBand {
        let lowerBound: Double
        let upperBound: Double
        let color: Color
        let label: String
    }

    /// A provisional cool-to-hot ramp, distinct from `TrainingMetricKind`'s own colors — heart-rate
    /// zone names/colors proper are still backlog (MVP1-54); this stands in until that ticket
    /// assigns real ones.
    private static func color(forZone zone: Int) -> Color {
        switch zone {
        case 1: .blue
        case 2: .green
        case 3: .yellow
        case 4: .orange
        default: .red
        }
    }

    /// The athlete's zone 1–5 range, padded by ``domainPadding`` on each side — see that
    /// property's own doc comment for why this doesn't also widen to fit the actual recorded data.
    private var domain: ClosedRange<Double> {
        guard let boundaries = histogram.zoneBoundariesBPM,
            let lower = boundaries.first, let upper = boundaries.last
        else { return Self.fallbackDomain }
        return (lower - Self.domainPadding)...(upper + Self.domainPadding)
    }

    private var zoneBands: [ZoneBand] {
        guard let boundaries = histogram.zoneBoundariesBPM, boundaries.count == 6 else { return [] }
        let labels = ["Z1", "Z2", "Z3", "Z4", "Z5"]
        return (0..<5).map { index in
            ZoneBand(
                lowerBound: boundaries[index],
                upperBound: boundaries[index + 1],
                color: Self.color(forZone: index + 1),
                label: labels[index]
            )
        }
    }

    /// `histogram` densified into one point per `binWidth`-wide step across `domain`, zero-filled
    /// where `histogram.bins` has no data — without this, `LineMark`'s catmullRom interpolation
    /// would smooth straight across the gaps between the (otherwise sparse) real bins instead of
    /// dipping to zero, which reads as heart-rate time existing where none was actually recorded.
    private var densifiedMinutesByBPM: [(bpm: Int, minutes: Double)] {
        let secondsByBin = Dictionary(uniqueKeysWithValues: histogram.bins.map { ($0.bpm, $0.seconds) })
        let binWidth = histogram.binWidth
        let lowerBin = Int((domain.lowerBound / Double(binWidth)).rounded(.down)) * binWidth
        let upperBin = Int((domain.upperBound / Double(binWidth)).rounded(.up)) * binWidth
        return stride(from: lowerBin, through: upperBin, by: binWidth).map { bpm in
            (bpm, (secondsByBin[bpm] ?? 0) / 60)
        }
    }

    /// The 80/20 polarized-training threshold (Seiler) — the heart rate below which 80% of the
    /// displayed week's training time falls. `nil` (so `chart` draws no rule) when there's no
    /// in-zone time recorded at all.
    private var eightyPercentileBPM: Double? {
        histogram.percentileBPM(0.8)
    }

    /// Whether `chart` has anything to show — deliberately keyed on ``eightyPercentileBPM`` (i.e.
    /// the same in-zone filter `HeartRateHistogram.percentileBPM(_:)` applies), not on
    /// `histogram.bins` directly: a week whose only recorded heart-rate samples fall below zone 1
    /// (e.g. warmup/cooldown-only, no real zone training) has *some* bin with recorded time, but
    /// every one of it sits outside `domain`, which only shows zone 1 through zone 5 — rendering
    /// `chart` for that week would just draw a flat, empty-looking line instead of the more honest
    /// "No Heart-Rate Data" placeholder.
    private var hasAnyTime: Bool {
        eightyPercentileBPM != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Time in Zone [min]")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Group {
                if hasAnyTime {
                    chart
                } else {
                    ContentUnavailableView(
                        "No Heart-Rate Data",
                        systemImage: "heart.slash",
                        description: Text("No heart-rate zones recorded this week.")
                    )
                }
            }
            .frame(height: 140)
            .padding(.horizontal)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(zoneBands, id: \.label) { band in
                RectangleMark(
                    xStart: .value("Lower", band.lowerBound),
                    xEnd: .value("Upper", band.upperBound)
                )
                .foregroundStyle(band.color.opacity(0.12))
            }
            // Drawn before the histogram line itself (so it renders behind it, per SwiftUI Charts'
            // declaration-order stacking) and thinner — a supporting reference, not a second series.
            if let eightyPercentileBPM {
                RuleMark(x: .value("80th percentile", eightyPercentileBPM))
                    .foregroundStyle(Color.gray)
                    .lineStyle(StrokeStyle(lineWidth: Self.percentileLineWidth))
            }
            ForEach(densifiedMinutesByBPM, id: \.bpm) { point in
                LineMark(x: .value("BPM", Double(point.bpm)), y: .value("Minutes", point.minutes))
                    .foregroundStyle(Color.primary)
                    .lineStyle(StrokeStyle(lineWidth: Self.smoothedLineWidth))
                    .interpolationMethod(.catmullRom)
            }
        }
        .chartXScale(domain: domain)
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let plotArea = geometry[plotFrame]
                    ForEach(zoneBands, id: \.label) { band in
                        let midValue = (band.lowerBound + band.upperBound) / 2
                        if let x = proxy.position(forX: midValue) {
                            Text(band.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .position(x: plotArea.minX + x, y: plotArea.minY + 10)
                        }
                    }
                    if let eightyPercentileBPM, let x = proxy.position(forX: eightyPercentileBPM) {
                        Text("80")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.gray))
                            // Near the bottom of the plot area, above where the x-axis itself
                            // renders (that's outside plotArea, in the margin below `maxY`).
                            .position(x: plotArea.minX + x, y: plotArea.maxY - 10)
                    }
                }
            }
        }
    }
}
