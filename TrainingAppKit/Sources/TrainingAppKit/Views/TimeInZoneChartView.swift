import Charts
import SwiftUI
import TrainingCore

/// The week view's graph panel "Time in zone" page (MVP1-55, design doc §2.1; histogram follow-up)
/// — a heart-rate histogram of the displayed week's activities, binned every 3 bpm, plotted over
/// muted background bands for each heart-rate zone (same visual language `FitnessChartView` uses
/// for TSB zones) with a single smoothed line tracing the time spent at each bpm.
///
/// Deliberately scoped to just the displayed week, not the 3-week window `FitnessChartView`/
/// `DailyLoadChartView` share: unlike load/CTL/ATL/TSB (already computed for the whole
/// `chartRange` by `TrainingModel.recompute`), the histogram here is built from raw samples on
/// demand (`WeekViewModel.heartRateHistogram()`), and widening that to 21 days would triple the
/// per-swipe-frame cost its memoization is built to avoid.
struct TimeInZoneChartView: View {
    let histogram: HeartRateHistogram

    private static let smoothedLineWidth: CGFloat = 3
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

    private var domain: ClosedRange<Double> {
        guard let boundaries = histogram.zoneBoundariesBPM,
            let lower = boundaries.first,
            let upper = boundaries.last
        else {
            guard let minBPM = histogram.bins.map(\.bpm).min(), let maxBPM = histogram.bins.map(\.bpm).max() else {
                return Self.fallbackDomain
            }
            return Double(minBPM)...Double(maxBPM + histogram.binWidth)
        }
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

    /// The histogram densified into one point per `binWidth`-wide step across `domain`, zero-filled
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

    private var hasAnyTime: Bool {
        histogram.bins.contains { $0.seconds > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Time in Zone")
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
            ForEach(densifiedMinutesByBPM, id: \.bpm) { point in
                LineMark(x: .value("BPM", point.bpm), y: .value("Minutes", point.minutes))
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
                }
            }
        }
    }
}
