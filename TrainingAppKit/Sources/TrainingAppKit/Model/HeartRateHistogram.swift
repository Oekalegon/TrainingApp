import Foundation
import TrainingCore

/// One bin of the week view's graph panel "Time in zone" page's heart-rate histogram (MVP1-55
/// follow-up) — `bpm` is the bin's lower bound, `seconds` the total time any activity in the
/// displayed week spent with a (consecutive-sample-averaged) heart rate in `bpm..<(bpm + binWidth)`.
public struct HeartRateHistogramBin: Hashable, Sendable {
    public let bpm: Int
    public let seconds: TimeInterval
}

/// A displayed week's heart-rate histogram, plus the athlete's current zone boundaries in bpm so
/// the chart can shade the same bands the old zone-by-day bars used to color, now against a
/// continuous bpm axis instead of discrete per-zone bars.
public struct HeartRateHistogram: Sendable {
    public let bins: [HeartRateHistogramBin]
    /// The bin width (in bpm) `bins` was built with — `TimeInZoneChartView` needs this to fill in
    /// the zero-time bins `bins` omits when it densifies the histogram into a continuous line.
    public let binWidth: Int
    /// `[zone1.lower, zone1.upper, zone2.upper, zone3.upper, zone4.upper, zone5.upper]` in bpm, or
    /// `nil` if the athlete's zone method can't resolve every zone (e.g. `.lactateThreshold` with
    /// no threshold heart rate recorded, or no heart-rate zone settings at all) — see
    /// `HeartRateZoneModel.zoneRatioRange(_:)`.
    public let zoneBoundariesBPM: [Double]?

    /// An empty histogram — `WeekViewModel`'s initial value before its first async load completes.
    public static let empty = HeartRateHistogram(bins: [], binWidth: 5, zoneBoundariesBPM: nil)

    /// Builds a histogram of `activities`' combined heart-rate samples, binned every `binWidth`
    /// bpm.
    ///
    /// Deliberately doesn't use `HeartRateSegmentIterator` (the same consecutive-sample,
    /// gap-skipping walk `TimeInZoneBuilder`/`ExponentialTRIMPCalculator` share to stay in
    /// agreement on what counts as "in the activity"): that type converts each sample pair into a
    /// heart-rate-reserve *ratio* trapezoid, which is exactly what a raw-bpm histogram doesn't
    /// want. This reimplements just its gap rule — a segment whose samples are `gapThresholdSeconds`
    /// or more apart is skipped as a pause — not its zone/TRIMP math, and bins each segment's
    /// average bpm directly.
    public static func aggregating(
        _ activities: [Activity],
        athlete: AthleteProfile,
        binWidth: Int = 5,
        gapThresholdSeconds: TimeInterval = 60
    ) -> HeartRateHistogram {
        var totals: [Int: TimeInterval] = [:]
        for activity in activities {
            let sorted = activity.heartRate.sorted { $0.time < $1.time }
            for (previous, current) in zip(sorted, sorted.dropFirst()) {
                let dt = current.time.timeIntervalSince(previous.time)
                guard dt > 0, dt <= gapThresholdSeconds else { continue }
                let averageBPM = (previous.bpm + current.bpm) / 2
                let bin = Int((averageBPM / Double(binWidth)).rounded(.down)) * binWidth
                totals[bin, default: 0] += dt
            }
        }
        let bins = totals
            .map { HeartRateHistogramBin(bpm: $0.key, seconds: $0.value) }
            .sorted { $0.bpm < $1.bpm }
        return HeartRateHistogram(
            bins: bins,
            binWidth: binWidth,
            zoneBoundariesBPM: zoneBoundariesBPM(for: athlete)
        )
    }

    /// The bpm below which `fraction` of the histogram's total time falls — e.g. `percentileBPM(0.8)`
    /// is the heart rate marking Seiler's 80/20 polarized-training threshold, the light-gray
    /// vertical line `TimeInZoneChartView` draws. Interpolates linearly within whichever bin's
    /// cumulative time first reaches `fraction` of the total, rather than snapping to that bin's
    /// own (`binWidth`-wide) edge. `nil` when the histogram has no time recorded at all.
    public func percentileBPM(_ fraction: Double) -> Double? {
        let total = bins.reduce(0) { $0 + $1.seconds }
        guard total > 0 else { return nil }
        let sorted = bins.sorted { $0.bpm < $1.bpm }
        let target = total * fraction
        var cumulative: TimeInterval = 0
        for bin in sorted {
            let cumulativeBeforeBin = cumulative
            cumulative += bin.seconds
            guard cumulative >= target else { continue }
            guard bin.seconds > 0 else { return Double(bin.bpm) }
            let fractionIntoBin = (target - cumulativeBeforeBin) / bin.seconds
            return Double(bin.bpm) + fractionIntoBin * Double(binWidth)
        }
        return sorted.last.map { Double($0.bpm) + Double(binWidth) }
    }

    /// Re-derives zone boundaries in bpm from the athlete's current `HeartRateZoneModel`, using
    /// only its public `zoneRatioRange(_:)` and the documented inverse of `deltaHRRatio(for:)` —
    /// `TimeInZoneBuilder.zoneBoundaries(_:)` computes the same thing but is internal to
    /// `TrainingCore`, so this is a small, display-only re-derivation rather than a reimplemented
    /// zone model.
    private static func zoneBoundariesBPM(for athlete: AthleteProfile) -> [Double]? {
        guard let settings = athlete.currentHeartRateZoneSettings else { return nil }
        let zoneModel = HeartRateZoneModel(settings: settings)
        guard let z1 = zoneModel.zoneRatioRange(1),
            let z2 = zoneModel.zoneRatioRange(2),
            let z3 = zoneModel.zoneRatioRange(3),
            let z4 = zoneModel.zoneRatioRange(4),
            let z5 = zoneModel.zoneRatioRange(5)
        else { return nil }
        func bpm(forRatio ratio: Double) -> Double {
            ratio * (zoneModel.maxHeartRateBPM - zoneModel.restingHeartRateBPM) + zoneModel.restingHeartRateBPM
        }
        return [z1.lowerBound, z1.upperBound, z2.upperBound, z3.upperBound, z4.upperBound, z5.upperBound]
            .map(bpm(forRatio:))
    }
}
