import Foundation
import TrainingCore

/// One bin of the week view's graph panel "Heart Rate Histogram" page's heart-rate histogram (MVP1-55
/// follow-up) — `bpm` is the bin's lower bound, `seconds` the total time any activity in the
/// displayed week spent with a (consecutive-sample-averaged) heart rate in `bpm..<(bpm + binWidth)`.
public struct HeartRateHistogramBin: Hashable, Sendable {
    public let bpm: Int
    public let seconds: TimeInterval
}

/// One point of `HeartRateHistogram.densifiedMinutes(domain:)`'s continuous, `binWidth`-stepped
/// line — see that method's own doc comment.
public struct HeartRateHistogramPoint: Hashable, Sendable {
    public let bpm: Int
    public let minutes: Double
}

/// A displayed week's heart-rate histogram, plus the athlete's current zone boundaries in bpm so
/// the chart can shade the same bands the old zone-by-day bars used to color, now against a
/// continuous bpm axis instead of discrete per-zone bars.
public struct HeartRateHistogram: Sendable {
    public let bins: [HeartRateHistogramBin]
    /// The bin width (in bpm) `bins` was built with — `HeartRateHistogramChartView` needs this to fill in
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

    /// The bpm below which `fraction` of the histogram's *in-zone* time falls — e.g.
    /// `percentileBPM(0.8)` is the heart rate marking Seiler's 80/20 polarized-training threshold,
    /// the light-gray vertical line `HeartRateHistogramChartView` draws. Interpolates linearly within
    /// whichever bin's cumulative time first reaches `fraction` of the total, rather than snapping
    /// to that bin's own (`binWidth`-wide) edge. `nil` when the histogram has no in-zone time
    /// recorded at all.
    ///
    /// Bins below `zoneBoundariesBPM`'s own Z1 lower bound (recovery heart rate, below the lowest
    /// zone Seiler's 80/20 split is even defined over) are excluded — without `zoneBoundariesBPM`
    /// (no resolvable zone settings), every bin counts. Nothing above the Z5 upper bound is
    /// excluded: `HeartRateZoneModel` bounds Z5 at the athlete's max heart rate, but a real sensor
    /// reading above that recorded max still belongs to "at or above Z5", not some undefined sixth
    /// zone, so it counts the same as any other in-zone time.
    public func percentileBPM(_ fraction: Double) -> Double? {
        let lowerBound = zoneBoundariesBPM?.first
        let inZoneBins = bins.filter { bin in lowerBound.map { Double(bin.bpm) >= $0 } ?? true }
        let total = inZoneBins.reduce(0) { $0 + $1.seconds }
        guard total > 0 else { return nil }
        let sorted = inZoneBins.sorted { $0.bpm < $1.bpm }
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

    /// `bins` densified into one point per `binWidth`-wide step across `domain`, zero-filled where
    /// `bins` has no data — without this, `HeartRateHistogramChartView`'s `LineMark` interpolation
    /// would smooth straight across the gaps between the (otherwise sparse) real bins instead of
    /// dipping to zero, which reads as heart-rate time existing where none was actually recorded.
    /// Real recorded time below zone 1 is included same as any other bin (it's meaningful — e.g.
    /// warmup/cooldown recovery heart rate); only `percentileBPM(_:)` excludes it, for the
    /// unrelated purpose of keeping the 80/20 threshold scoped to in-zone time.
    ///
    /// `bins`' keys sit on a fixed `binWidth` grid independent of `domain`'s own edges (a caller
    /// like `HeartRateHistogramChartView` typically derives `domain` from the athlete's zone
    /// boundaries, which don't fall on that grid), so flooring/ceiling `domain`'s bounds to the
    /// nearest bin can land one bin *outside* `domain` on either side. The trailing `filter` drops
    /// any such out-of-domain point rather than letting its real (nonzero) value leak in — without
    /// it, the line between that point and the next in-domain one would render already-risen right
    /// at the domain edge instead of reading zero there, which is what made the histogram chart's
    /// curve look like it started before its own x-axis did (MVP1-61).
    public func densifiedMinutes(domain: ClosedRange<Double>) -> [HeartRateHistogramPoint] {
        let secondsByBin = Dictionary(uniqueKeysWithValues: bins.map { ($0.bpm, $0.seconds) })
        let lowerBin = Int((domain.lowerBound / Double(binWidth)).rounded(.down)) * binWidth
        let upperBin = Int((domain.upperBound / Double(binWidth)).rounded(.up)) * binWidth
        return stride(from: lowerBin, through: upperBin, by: binWidth)
            .filter { Double($0) >= domain.lowerBound && Double($0) <= domain.upperBound }
            .map { HeartRateHistogramPoint(bpm: $0, minutes: (secondsByBin[$0] ?? 0) / 60) }
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
