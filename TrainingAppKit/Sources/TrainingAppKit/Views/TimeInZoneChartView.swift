import Charts
import SwiftUI
import TrainingCore

/// The week view's graph panel "Time in zone" page (MVP1-55, design doc §2.1; histogram follow-up)
/// — a heart-rate histogram of the displayed week's activities, binned every 5 bpm, plotted over
/// muted background bands for each heart-rate zone (same visual language `FitnessChartView` uses
/// for TSB zones) with a single smoothed line tracing the time spent at each bpm, a light-gray
/// rule (labeled with an "80" pill) at the 80th percentile (Seiler's 80/20 polarized-training
/// threshold), and a very thin grey line per activity underneath the combined one.
///
/// Deliberately scoped to just the displayed week, not the 3-week window `FitnessChartView`/
/// `DailyLoadChartView` share: unlike load/CTL/ATL/TSB (already computed for the whole
/// `chartRange` by `TrainingModel.recompute`), the histogram here is built from raw samples —
/// see `WeekViewModel.heartRateHistogram`'s own doc comment for why that's computed
/// asynchronously off the main actor rather than synchronously here — and widening the window to
/// 21 days would triple the cost of every recomputation.
struct TimeInZoneChartView: View {
    let histogram: HeartRateHistogram
    /// Each of the displayed week's activities' own heart-rate histogram, drawn as a very thin
    /// grey line under `histogram`'s own combined one — see
    /// `WeekViewModel.perActivityHeartRateHistograms`'s own doc comment for why this fills in
    /// progressively rather than arriving all at once.
    let perActivityHistograms: [HeartRateHistogram]

    private static let smoothedLineWidth: CGFloat = 3
    /// Thinner than `smoothedLineWidth` and drawn before it in `chart` (so it sits behind), per
    /// the 80/20 polarized-training threshold's supporting role — it marks a reference point on
    /// the histogram, not a second series competing with it.
    private static let percentileLineWidth: CGFloat = 1
    /// Thinner still — one of these draws per activity, so even a handful of them shouldn't read
    /// as more prominent than the single combined line they sit underneath.
    private static let perActivityLineWidth: CGFloat = 0.5
    /// Padding (in bpm) added on either side of the athlete's zone 1–5 range, so the lowest/
    /// highest zone don't get clipped to a zero-width sliver at the domain's own edge — mirrors
    /// `FitnessChartView.formDomain`'s own padding around its zone boundaries.
    private static let domainPadding: Double = 6
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

    /// The zone-based range (zone 1's lower bound through zone 5's upper, padded) widened to also
    /// fully contain every bin with actual recorded time, in either direction — real heart-rate
    /// data routinely dips below zone 1 (warmup, cool-down, rest between intervals) or reaches
    /// above zone 5 (a hard effort at max heart rate), and a domain sized only to the *athlete's*
    /// zone boundaries clipped that real data at both edges instead of showing it taper to zero.
    private var domain: ClosedRange<Double> {
        var range = histogram.zoneBoundariesBPM.flatMap { boundaries -> ClosedRange<Double>? in
            guard let lower = boundaries.first, let upper = boundaries.last else { return nil }
            return (lower - Self.domainPadding)...(upper + Self.domainPadding)
        } ?? Self.fallbackDomain

        let recordedBins = histogram.bins.filter { $0.seconds > 0 }
        if let minBPM = recordedBins.map(\.bpm).min() {
            range = min(range.lowerBound, Double(minBPM) - Self.domainPadding)...range.upperBound
        }
        if let maxBPM = recordedBins.map(\.bpm).max() {
            range = range.lowerBound...max(range.upperBound, Double(maxBPM + histogram.binWidth) + Self.domainPadding)
        }
        return range
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
        Self.densifiedMinutes(for: histogram, domain: domain)
    }

    /// Same densification as ``densifiedMinutesByBPM``, generalized so `chart` can also apply it
    /// to each of `perActivityHistograms` against the shared `domain` those lines and the combined
    /// one all plot against.
    private static func densifiedMinutes(
        for histogram: HeartRateHistogram, domain: ClosedRange<Double>
    ) -> [(bpm: Int, minutes: Double)] {
        let secondsByBin = Dictionary(uniqueKeysWithValues: histogram.bins.map { ($0.bpm, $0.seconds) })
        let binWidth = histogram.binWidth
        let lowerBin = Int((domain.lowerBound / Double(binWidth)).rounded(.down)) * binWidth
        let upperBin = Int((domain.upperBound / Double(binWidth)).rounded(.up)) * binWidth
        return stride(from: lowerBin, through: upperBin, by: binWidth).map { bpm in
            (bpm, (secondsByBin[bpm] ?? 0) / 60)
        }
    }

    /// One activity's own densified point, flattened out of `perActivityHistograms` up front so
    /// `chart` is a single flat `ForEach` rather than a nested one — the nested form (a `ForEach`
    /// of activities, each containing a `ForEach` of bpm points) was the exact pattern that made
    /// the type checker give up elsewhere in this file's history (see git blame); flattening avoids
    /// it here too.
    private struct PerActivityPoint: Identifiable {
        /// A `String`, not the plain `Int` index — Swift Charts infers a raw `Int`/`Double`
        /// `foregroundStyle(by:)` domain as a *continuous* (quantitative) scale rather than a
        /// *discrete* one, which crashed deep inside Charts itself. `FitnessChartView`'s own
        /// `foregroundStyle(by:)` series (`"Form (raw)"`, `"Form (smoothed)"`, etc.) use `String`
        /// keys for the same reason.
        let activitySeriesKey: String
        let bpm: Int
        let minutes: Double
        var id: String { "\(activitySeriesKey)-\(bpm)" }
    }

    private var perActivityPoints: [PerActivityPoint] {
        perActivityHistograms.enumerated().flatMap { index, histogram in
            Self.densifiedMinutes(for: histogram, domain: domain).map { point in
                PerActivityPoint(activitySeriesKey: "Activity \(index)", bpm: point.bpm, minutes: point.minutes)
            }
        }
    }

    private var hasAnyTime: Bool {
        histogram.bins.contains { $0.seconds > 0 }
    }

    /// The 80/20 polarized-training threshold (Seiler) — the heart rate below which 80% of the
    /// displayed week's training time falls. `nil` (so `chart` draws no rule) when there's no time
    /// recorded at all.
    private var eightyPercentileBPM: Double? {
        histogram.percentileBPM(0.8)
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

    /// Split out of `chart` so `.chartForegroundStyleScale(domain:range:)` (below) can be applied
    /// conditionally: passing it an empty `domain`/`range` — which happens whenever
    /// `perActivityHistograms` is still empty, e.g. every render before its first async load
    /// completes — crashes deep inside Charts itself (an `EXC_BREAKPOINT` in Charts' own internal
    /// scale setup, not a Swift-level precondition with a useful message).
    @ViewBuilder
    private var chart: some View {
        if perActivityHistograms.isEmpty {
            chartMarks
        } else {
            let seriesKeys = perActivityHistograms.indices.map { "Activity \($0)" }
            chartMarks
                .chartForegroundStyleScale(
                    domain: seriesKeys,
                    range: Array(repeating: Color.gray.opacity(0.5), count: seriesKeys.count)
                )
        }
    }

    private var chartMarks: some View {
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
            // Also drawn before the combined line, same reasoning — each activity's own histogram
            // is a supporting detail underneath the week's combined one, not a competing series.
            // `.foregroundStyle(by:)` (with every index mapped to the same grey right below) is
            // what keeps each activity's points from being connected into one zigzagging line
            // across activities -- without a distinguishing series, Swift Charts sorts every point
            // sharing a style by x and threads them into a single path.
            ForEach(perActivityPoints) { point in
                // `Double(point.bpm)`, not the plain `Int` — every mark in this chart plots "BPM"
                // on x (this one, the combined line below, the zone bands, and the percentile
                // rule), and mixing `Int` and `Double` plot values across marks sharing the same
                // axis is a documented source of Charts crashing internally on real data; keeping
                // one consistent type for that role avoids it.
                LineMark(x: .value("BPM", Double(point.bpm)), y: .value("Minutes", point.minutes))
                    .foregroundStyle(by: .value("Activity", point.activitySeriesKey))
                    .lineStyle(StrokeStyle(lineWidth: Self.perActivityLineWidth))
                    .interpolationMethod(.catmullRom)
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
