import CoreGraphics
import Foundation

/// The geometry of the zone dial (WATCH-118): all the zones on one horizontal line, lowest on the
/// left, so a rising heart rate moves to the right.
///
/// The zones sit along it by their place against the target zone, in three stretches that keep the
/// target in the middle:
/// - the zones **below** the target first, on the left, with zone 0 (below zone 1) half the size of
///   the others (the whole stretch when the target is zone 1);
/// - the **target zone**, in the middle;
/// - the zones **above** it, equal, on the right.
///
/// A new target lays the line out again. ``spans(target:length:)`` blends two layouts when the target
/// is between two zones, so the change can be animated.
///
/// Pure arithmetic, so it can be tested without a screen; `ZoneDialBar` draws it.
public enum ZoneDial {
    /// The share of the line the zones below the target, the target and the zones above it take.
    /// A stretch with no zones in it (nothing above a zone 5 target) is left empty.
    public static let shares = (below: 0.35, target: 0.30, above: 0.35)

    /// Where a zone lies along the line, as distances from its left end.
    public struct Span: Sendable, Hashable {
        public var start: Double
        public var end: Double
        public var length: Double { end - start }
    }

    /// Where each zone, 0 to 5, lies along a line for a whole-number target.
    ///
    /// - Parameters:
    ///   - target: The target zone, 1 to 5.
    ///   - length: The length of the line.
    /// - Returns: Six spans, by zone number.
    public static func spans(target: Int, length: Double) -> [Span] {
        let target = min(max(target, 1), 5)
        var spans = [Span](repeating: Span(start: 0, end: 0), count: 6)
        let total = length
        let belowEnd = total * shares.below
        let targetEnd = belowEnd + total * shares.target
        // Below the target: zone 0, half a size unless it is alone, then the zones up to the target.
        let weights = (0..<target).map { zone in zone == 0 && target > 1 ? 0.5 : 1.0 }
        let weightTotal = weights.reduce(0, +)
        var cursor = 0.0
        for zone in 0..<target {
            let length = belowEnd * weights[zone] / weightTotal
            spans[zone] = Span(start: cursor, end: cursor + length)
            cursor += length
        }
        spans[target] = Span(start: belowEnd, end: targetEnd)
        // Above the target: equal, the nearest to the target first, the last ending at the gap.
        let above = 5 - target
        if above > 0 {
            let length = (total * shares.above) / Double(above)
            for (index, zone) in ((target + 1)...5).enumerated() {
                let start = targetEnd + Double(index) * length
                spans[zone] = Span(start: start, end: start + length)
            }
        }
        return spans
    }

    /// Where each zone lies for a target that may be between two zones, while the ring changes
    /// over from one to the other: the two layouts blended by how far along the target is.
    ///
    /// - Parameters:
    ///   - target: The target zone, 1 to 5, or between two.
    ///   - length: The length of the line.
    public static func spans(target: Double, length: Double) -> [Span] {
        let clamped = min(max(target, 1), 5)
        let low = Int(clamped.rounded(.down))
        let high = min(low + 1, 5)
        let fraction = clamped - Double(low)
        let a = spans(target: low, length: length)
        guard fraction > 0 else { return a }
        let b = spans(target: high, length: length)
        return (0...5).map { zone in
            Span(
                start: a[zone].start + (b[zone].start - a[zone].start) * fraction,
                end: a[zone].end + (b[zone].end - a[zone].end) * fraction)
        }
    }

    /// The distance along the line of a position along the zones (see
    /// ``ZoneBands/position(forHeartRate:)``): inside its zone's span, by how far through the zone it is.
    ///
    /// - Parameters:
    ///   - position: Where the heart rate is along the zones, 0 to 6.
    ///   - spans: The zones' spans, from `spans(target:length:)`.
    public static func distance(forPosition position: Double, in spans: [Span]) -> Double {
        let position = min(max(position, 0), 6)
        let zone = min(Int(position.rounded(.down)), 5)
        let span = spans[zone]
        return span.start + (position - Double(zone)) * span.length
    }
}
