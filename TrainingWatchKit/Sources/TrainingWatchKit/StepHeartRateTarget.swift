import Foundation
import TrainingCore

/// A step's heart-rate target in bpm, with the run screen's questions about it (WATCH-105): where a
/// reading sits against it, and where to draw it on a gauge. Plain bounds with no smoothing or
/// hysteresis; deciding when to alert is WATCH-106's job.
public struct StepHeartRateTarget: Sendable, Hashable {
    /// Where a heart rate is against the target.
    public enum Position: Sendable, Hashable {
        /// Under the target's lower bound, by this many bpm.
        case below(Double)
        /// Within the target, bounds included.
        case inside
        /// Over the target's upper bound, by this many bpm.
        case above(Double)
    }

    /// The target as a short label: "Z4", "Z3.5-4.0" or "150-160 bpm".
    public let label: String
    /// The target's heart-rate range in bpm.
    public let bpm: ClosedRange<Double>
    /// The zone (1 to 5) the target is in, for the zone dial: the zone itself, the zone a stretch
    /// of zones starts in, or the zone of the middle of a bpm range.
    public let zone: Int

    /// The heart-rate target of `step`, in bpm.
    ///
    /// A whole zone or a stretch of zones needs the athlete's zones to be turned into bpm, so
    /// without them (`bands` is `nil`) only a target written in bpm resolves. A step with a pace,
    /// power or RPE target and no heart-rate one has none.
    ///
    /// - Parameters:
    ///   - step: The step being run.
    ///   - bands: The athlete's zone bands, or `nil` when no zones have arrived.
    public init?(step: WorkoutStep, bands: ZoneBands?) {
        guard let target = WatchWorkoutSummary.heartRateTarget(of: step) else { return nil }
        switch target {
        case .heartRateZone(let zone):
            guard let range = bands?.range(of: zone) else { return nil }
            self.init(label: "Z\(zone)", bpm: range, zone: min(max(zone, 1), 5))
        case .heartRateZoneRange(let positions):
            guard let bands, let low = Self.bpm(atPosition: positions.lowerBound, in: bands),
                  let high = Self.bpm(atPosition: positions.upperBound, in: bands) else { return nil }
            let zone = positions.lowerBound.rounded(.down)
            let whole = positions.lowerBound == zone && positions.upperBound == zone + 1
            self.init(
                label: whole ? "Z\(Int(zone))" : String(format: "Z%.1f-%.1f", positions.lowerBound, positions.upperBound),
                bpm: min(low, high)...max(low, high),
                zone: min(max(Int(zone), 1), 5))
        case .heartRateRange(let low, let high):
            let middle = (low + high) / 2
            self.init(
                label: "\(Int(low.rounded()))-\(Int(high.rounded())) bpm", bpm: min(low, high)...max(low, high),
                zone: min(max(bands?.zone(forHeartRate: middle) ?? 1, 1), 5))
        case .phaseIntensity, .pace, .power, .rpe:
            return nil
        }
    }

    private init(label: String, bpm: ClosedRange<Double>, zone: Int) {
        self.label = label
        self.bpm = bpm
        self.zone = zone
    }

    /// A zone position (`n.0` the bottom of zone `n`, 6.0 the top of zone 5, as TrainingKit has them)
    /// as bpm.
    private static func bpm(atPosition position: Double, in bands: ZoneBands) -> Double? {
        let zone = min(max(Int(position.rounded(.down)), 1), 5)
        guard let range = bands.range(of: zone) else { return nil }
        let fraction = min(max(position - Double(zone), 0), 1)
        return range.lowerBound + fraction * (range.upperBound - range.lowerBound)
    }

    /// Where `heartRate` is against the target.
    public func position(forHeartRate heartRate: Double) -> Position {
        if heartRate < bpm.lowerBound { return .below(bpm.lowerBound - heartRate) }
        if heartRate > bpm.upperBound { return .above(heartRate - bpm.upperBound) }
        return .inside
    }

    /// Whether a heart rate is under, in or over the target, for the zone dial's background: out of the
    /// target only when beyond a bound by a margin (a tenth of the target's width, at least 1 bpm,
    /// as for the alerts), so a reading hovering on a bound doesn't make the screen flicker.
    public enum Status: Sendable, Hashable { case below, inside, above }

    /// - Parameter heartRate: The heart rate in bpm.
    public func status(forHeartRate heartRate: Double) -> Status {
        let margin = max((bpm.upperBound - bpm.lowerBound) * 0.1, 1)
        if heartRate < bpm.lowerBound - margin { return .below }
        if heartRate > bpm.upperBound + margin { return .above }
        return .inside
    }

    /// The target as a stretch along the zones (``ZoneBands/position(forHeartRate:)``), for drawing
    /// it on the zone dial's top bar: a whole zone is `n.0...n+1.0`, and a stretch such as Z4.0-4.5 or
    /// 150-160 bpm only part of one.
    ///
    /// - Parameter bands: The athlete's zone bands.
    public func positions(in bands: ZoneBands) -> ClosedRange<Double> {
        bands.position(forHeartRate: bpm.lowerBound)...bands.position(forHeartRate: bpm.upperBound)
    }

    /// Where to draw `heartRate` on a gauge, 0 to 1: the target takes the middle half (0.25 to 0.75)
    /// and the gauge reaches half a target's width beyond each end, so a reading just outside is
    /// still plainly inside the gauge. Clamped, so a far-off reading sits at an end.
    public func gaugePosition(forHeartRate heartRate: Double) -> Double {
        let width = max(bpm.upperBound - bpm.lowerBound, 1)
        let low = bpm.lowerBound - width / 2
        return min(max((heartRate - low) / (width * 2), 0), 1)
    }
}

extension StepHeartRateTarget.Position {
    /// What a person is told about it: "In target", "8 bpm below" or "5 bpm above".
    public var text: String {
        switch self {
        case .inside: "In target"
        case .below(let bpm): "\(Int(bpm.rounded(.up))) bpm below"
        case .above(let bpm): "\(Int(bpm.rounded(.up))) bpm above"
        }
    }
}
