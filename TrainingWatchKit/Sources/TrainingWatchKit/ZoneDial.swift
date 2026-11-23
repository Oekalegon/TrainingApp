import CoreGraphics
import Foundation

/// The geometry of the zone dial (WATCH-118): all the zones on one horizontal line in their own
/// order, zone 0 (below zone 1) on the left to zone 5 on the right, so a rising heart rate moves to
/// the right. Every zone is the same size except the target zone, which is three times as wide. The target
/// is therefore a bit to the left of the middle for a low target zone and to the right of it for a
/// high one.
///
/// A new target lays the line out again. ``spans(target:length:)`` blends two layouts when the target
/// is between two zones, so the change can be animated.
///
/// Pure arithmetic, so it can be tested without a screen; `ZoneDialBar` draws it.
public enum ZoneDial {
    /// How many times as wide the target zone is as each of the other zones.
    public static let targetWidth = 3.0

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
        let weights = (0...5).map { $0 == target ? targetWidth : 1.0 }
        let unit = length / weights.reduce(0, +)
        var cursor = 0.0
        return weights.map { weight in
            defer { cursor += weight * unit }
            return Span(start: cursor, end: cursor + weight * unit)
        }
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
