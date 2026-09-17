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

/// A displayed week's heart-rate histogram, plus the zone boundaries (in bpm) effective by the end
/// of that week, so the chart can shade the same bands the old zone-by-day bars used to color, now
/// against a continuous bpm axis instead of discrete per-zone bars.
public struct HeartRateHistogram: Sendable {
    public let bins: [HeartRateHistogramBin]
    /// The bin width (in bpm) `bins` was built with — `HeartRateHistogramChartView` needs this to fill in
    /// the zero-time bins `bins` omits when it densifies the histogram into a continuous line.
    public let binWidth: Int
    /// `[zone1.lower, zone1.upper, zone2.upper, zone3.upper, zone4.upper, zone5.upper]` in bpm, or
    /// `nil` if the athlete's zone method can't resolve every zone (e.g. `.lactateThreshold` with
    /// no threshold heart rate recorded, or no heart-rate zone settings at all) — see
    /// `HeartRateZoneModel.zoneRatioRange(_:)`. Resolved as of the *displayed week's own end date*
    /// (``aggregating(_:athlete:asOf:statisticsCalculator:binWidth:gapThresholdSeconds:)``'s `asOf`),
    /// not the athlete's current settings — a week long in the past should shade against the zones
    /// that were actually in effect back then, not whatever the athlete's zones happen to be today
    /// (MVP1-78 follow-up). Shades `HeartRateHistogramChartView`'s bpm chart and gates
    /// ``percentileBPM(_:)``/``minutesByZone()``'s `nil` case; the zone *minutes* themselves come
    /// from `timeInZone` below, not from these boundaries (see ``minutesByZone()``'s own doc
    /// comment for why the two must stay separate — MVP1-78).
    public let zoneBoundariesBPM: [Double]?
    /// Each activity's own ``StatisticsCalculator/summary(for:athlete:)`` time-in-zone, summed —
    /// the same per-activity, date-effective-zone-settings computation the week's LIT% stat tile
    /// rolls up, kept here instead of re-derived from `bins` so ``minutesByZone()`` agrees with it
    /// (MVP1-78).
    private let timeInZone: TimeInZone

    /// - Parameter timeInZone: Defaults to empty for callers (mostly tests) that only care about
    ///   `bins`/`zoneBoundariesBPM`-driven behavior and don't exercise ``minutesByZone()``.
    public init(
        bins: [HeartRateHistogramBin],
        binWidth: Int,
        zoneBoundariesBPM: [Double]?,
        timeInZone: TimeInZone = TimeInZone()
    ) {
        self.bins = bins
        self.binWidth = binWidth
        self.zoneBoundariesBPM = zoneBoundariesBPM
        self.timeInZone = timeInZone
    }

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
    ///
    /// - Parameters:
    ///   - asOf: The date `zoneBoundariesBPM` resolves zone settings as of — callers should pass
    ///     the *displayed week's own end date*, not `.now`/today, so a week long in the past shades
    ///     against the zones that were actually in effect that week rather than the athlete's
    ///     current ones (MVP1-78 follow-up). Using the week's end (rather than, say, its start or
    ///     an average across it) picks up the latest zone-settings change that happened *during*
    ///     the week, matching how `heartRateZoneSettings(asOf:)` is already used per-activity below.
    ///   - gapThresholdSeconds: Defaults to `statisticsCalculator`'s own `gapThresholdSeconds`
    ///     rather than an independent literal, so the raw-bpm `bins` this builds and the `timeInZone`
    ///     `statisticsCalculator` computes always agree on which segments count as "in the
    ///     activity" — passing a different value here than `statisticsCalculator` uses would let
    ///     the bpm chart and the zone-minutes breakdown silently disagree again, the same class of
    ///     bug MVP1-78 fixed for zone *settings*.
    public static func aggregating(
        _ activities: [Activity],
        athlete: AthleteProfile,
        asOf: Date,
        statisticsCalculator: StatisticsCalculator = StatisticsCalculator(),
        binWidth: Int = 5,
        gapThresholdSeconds: TimeInterval? = nil
    ) -> HeartRateHistogram {
        let gapThresholdSeconds = gapThresholdSeconds ?? statisticsCalculator.gapThresholdSeconds
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
        // Each activity's own date-effective zone settings, not one shared boundary set for the
        // whole week — two activities in the same week can legitimately have different zone
        // boundaries in bpm if the athlete's zone settings changed between them (MVP1-78).
        let timeInZone = activities.reduce(TimeInZone()) { partial, activity in
            partial + statisticsCalculator.summary(for: activity, athlete: athlete).timeInZone
        }
        return HeartRateHistogram(
            bins: bins,
            binWidth: binWidth,
            zoneBoundariesBPM: zoneBoundariesBPM(for: athlete, asOf: asOf),
            timeInZone: timeInZone
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

    /// Time spent in each of zones 1 through 5, from `timeInZone` — each activity's own
    /// date-effective zone settings summed across the week, the same computation and the same
    /// numbers the week's LIT% stat tile is built from (``StatisticsCalculator/summary(for:athlete:)``,
    /// rolled up via `TimeInZone.+`).
    ///
    /// Deliberately *not* derived from `bins`/`zoneBoundariesBPM`: those bin the week's raw bpm
    /// samples against one shared boundary set (the athlete's *current* zone settings), which
    /// silently misclassifies any activity whose own zone settings (effective on its own date)
    /// differed from that shared set — e.g. two activities both at 136 bpm, one on a day zone 2's
    /// upper limit was 137 bpm and the other on a day it was 135 bpm, need 20 minutes credited to
    /// zone 2 *and* 20 to zone 3, not 40 minutes bucketed under whichever boundary happened to be
    /// current (MVP1-78).
    ///
    /// Every zone appears in the result, in zone order, with 0 minutes if untouched — matching the
    /// "list every zone, not just the ones reached" convention `ActivityDetailView`'s own
    /// time-in-zone breakdown uses (MVP1-70). `nil` when `zoneBoundariesBPM` itself couldn't
    /// resolve (`heartRateZoneHistory` empty, or the zone method can't resolve as of the week's own
    /// end date) — note this guard and `timeInZone`'s own data can, in a narrow edge case, disagree:
    /// an athlete using `.lactateThreshold` zoning whose settings changed *during* the displayed
    /// week could have the week-end `asOf` resolve fully while one specific activity's own,
    /// earlier-in-the-week settings don't (e.g. no LTHR recorded yet that day), silently
    /// contributing 0 seconds for that activity rather than `nil` for the whole week.
    public func minutesByZone() -> [(zone: HeartRateZone, minutes: Double)]? {
        guard zoneBoundariesBPM != nil else { return nil }
        return HeartRateZone.allCases.map { zone in
            (zone, (timeInZone.seconds[zone.rawValue] ?? 0) / 60)
        }
    }

    /// Re-derives zone boundaries in bpm from the `HeartRateZoneModel` effective on `asOf`, using
    /// only `HeartRateZoneModel`'s public `zoneRatioRange(_:)` and the documented inverse of
    /// `deltaHRRatio(for:)` — `TimeInZoneBuilder.zoneBoundaries(_:)` computes the same thing but is
    /// internal to `TrainingCore`, so this is a small, display-only re-derivation rather than a
    /// reimplemented zone model. Uses `heartRateZoneSettings(asOf:)`, not
    /// `currentHeartRateZoneSettings` — see `zoneBoundariesBPM`'s own doc comment for why.
    private static func zoneBoundariesBPM(for athlete: AthleteProfile, asOf: Date) -> [Double]? {
        guard let settings = athlete.heartRateZoneSettings(asOf: asOf) else { return nil }
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
