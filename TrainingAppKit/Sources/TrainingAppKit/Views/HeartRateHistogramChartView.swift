import Charts
import SwiftUI
import TrainingCore

/// The week view's graph panel "Heart Rate Histogram" page (MVP1-55, design doc §2.1;
/// histogram follow-up) — a heart-rate histogram of the displayed week's activities, binned
/// every 5 bpm, plotted over muted background bands for each heart-rate zone (same visual
/// language `FitnessChartView` uses for TSB zones) with a single smoothed line tracing the time
/// spent at each bpm, and a light-gray rule (labeled with an "80" pill) at the 80th percentile
/// (Seiler's 80/20 polarized-training threshold).
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
struct HeartRateHistogramChartView: View {
    let histogram: HeartRateHistogram

    private static let smoothedLineWidth: CGFloat = 3
    /// Thinner than `smoothedLineWidth` and drawn before it in `chart` (so it sits behind), per
    /// the 80/20 polarized-training threshold's supporting role — it marks a reference point on
    /// the histogram, not a second series competing with it.
    private static let percentileLineWidth: CGFloat = 1
    /// Padding (in bpm) added below zone 1's lower bound and above zone 5's upper bound — the
    /// histogram is deliberately scoped to the zones themselves (design intent: this is a "time in
    /// zone" chart, not a general heart-rate distribution), not widened to fit whatever the actual
    /// recorded data happens to span. Also gives the line a bit of zero-filled runway (see
    /// `densifiedMinutesByBPM`) before the domain's own edge, so it visibly reads as decaying to
    /// zero rather than still looking like a non-zero value right at the boundary.
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
        return HeartRateZone.allCases.map { zone in
            let index = zone.rawValue - 1
            return ZoneBand(
                lowerBound: boundaries[index],
                upperBound: boundaries[index + 1],
                color: zone.color,
                // Short "Z1"-style label, not `zone.displayName` — this annotates a narrow band
                // directly on the chart, where a full name like "Threshold" wouldn't fit.
                label: "Z\(zone.rawValue)"
            )
        }
    }

    /// `histogram` densified into one point per `binWidth`-wide step across `domain`, zero-filled
    /// where `histogram.bins` has no data — without this, `LineMark`'s interpolation would smooth
    /// straight across the gaps between the (otherwise sparse) real bins instead of dipping to
    /// zero, which reads as heart-rate time existing where none was actually recorded. Real
    /// recorded time below zone 1 is shown here same as any other bin (it's meaningful — e.g.
    /// warmup/cooldown recovery heart rate), not zeroed out; only ``HeartRateHistogram
    /// .percentileBPM(_:)`` excludes it, for the unrelated purpose of keeping the 80/20 threshold
    /// scoped to in-zone time.
    ///
    /// `histogram.bins`' keys sit on a fixed `binWidth` grid independent of `domain`'s own edges
    /// (`domain` is offset from the athlete's zone boundaries, which don't fall on that grid), so
    /// flooring/ceiling `domain.lowerBound`/`domain.upperBound` to the nearest bin can land one bin
    /// *outside* `domain` on either side. Left unfiltered, a real (nonzero) bin just past that edge
    /// got plotted, and the portion of the line between it and the next in-domain point rendered
    /// already-risen right at the domain edge instead of reading zero there — visually, the curve
    /// looked like it started before the x-axis' own left edge (MVP1-61). The trailing `filter`
    /// drops any such out-of-domain point so nothing renders past what `chartXScale(domain:)`
    /// actually shows.
    private var densifiedMinutesByBPM: [(bpm: Int, minutes: Double)] {
        let secondsByBin = Dictionary(uniqueKeysWithValues: histogram.bins.map { ($0.bpm, $0.seconds) })
        let binWidth = histogram.binWidth
        let lowerBin = Int((domain.lowerBound / Double(binWidth)).rounded(.down)) * binWidth
        let upperBin = Int((domain.upperBound / Double(binWidth)).rounded(.up)) * binWidth
        return stride(from: lowerBin, through: upperBin, by: binWidth)
            .filter { Double($0) >= domain.lowerBound && Double($0) <= domain.upperBound }
            .map { bpm in (bpm, (secondsByBin[bpm] ?? 0) / 60) }
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
            Text("Heart Rate Histogram")
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
                    // `.monotone`, not `.catmullRom`: at the zero-filled/real-data boundary (a
                    // sharp jump from 0 to the first real bin's minutes), catmullRom's tangent at
                    // the zero point ahead of that jump is pulled toward the nonzero point after
                    // it, so the curve visibly starts rising several bpm before the real data
                    // begins (MVP1-61) — `.monotone` doesn't overshoot past the values it's
                    // actually interpolating between.
                    .interpolationMethod(.monotone)
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
