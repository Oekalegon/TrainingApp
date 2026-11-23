import CoreGraphics
import Foundation

/// The geometry of the zone dial (WATCH-118): a round ring, like a gauge, with a gap at the bottom.
/// It starts at the lower left, runs clockwise up the left side, over the top and down the right side
/// to the lower right. Zone 0 (below zone 1) comes first and zone 5 last, so a rising heart rate
/// moves clockwise.
///
/// The zones sit along it by their place against the target zone, in three stretches that keep the
/// target on top:
/// - the zones **below** the target first, on the left, with zone 0 half the size of the others (the
///   whole stretch when the target is zone 1);
/// - the **target zone**, in the middle, centred on the top;
/// - the zones **above** it, equal, on the right.
///
/// A new target lays the ring out again. ``spans(target:outline:)`` blends two layouts when the
/// target is between two zones, so the change can be animated.
///
/// Pure arithmetic, so it can be tested without a screen; `ZoneDialRing` draws it.
public enum ZoneDial {
    /// The share of the ring the zones below the target, the target and the zones above it take.
    /// A stretch with no zones in it (nothing above a zone 5 target) is left empty.
    public static let shares = (below: 0.35, target: 0.30, above: 0.35)

    /// The ring's outline: an arc of a circle, open at the bottom, measured along its length from
    /// the start at the lower left, clockwise.
    public struct Outline: Sendable, Hashable {
        /// The middle of the circle.
        public let center: CGPoint
        public let radius: Double
        /// The angle left open at the bottom, in degrees.
        public let gapAngle: Double
        /// The angle the ring starts at, degrees clockwise from the top: the lower left.
        public var startAngle: Double { 180 + gapAngle / 2 }
        /// The length of the whole outline.
        public var totalLength: Double { radius * (360 - gapAngle) * .pi / 180 }

        /// - Parameters:
        ///   - center: The middle of the circle.
        ///   - radius: The circle's radius, along the middle of the ring's stroke.
        ///   - gapAngle: The angle left open at the bottom, 0 to 340 degrees.
        public init(center: CGPoint, radius: Double, gapAngle: Double) {
            self.center = center
            self.radius = max(radius, 0)
            self.gapAngle = min(max(gapAngle, 0), 340)
        }

        /// The point at `distance` along the outline, with the angle its outward normal points at
        /// (degrees clockwise from the top, 0 to 360). A distance beyond the ends is held at the end.
        public func point(at distance: Double) -> (point: CGPoint, outward: Double) {
            let d = min(max(distance, 0), totalLength)
            let angle = startAngle + (radius > 0 ? d / radius * 180 / .pi : 0)
            let radians = angle * .pi / 180
            var outward = angle.truncatingRemainder(dividingBy: 360)
            if outward < 0 { outward += 360 }
            return (
                CGPoint(x: Double(center.x) + radius * sin(radians), y: Double(center.y) - radius * cos(radians)),
                outward)
        }
    }

    /// Where a zone lies along the outline, as distances from its start.
    public struct Span: Sendable, Hashable {
        public var start: Double
        public var end: Double
        public var length: Double { end - start }
    }

    /// Where each zone, 0 to 5, lies along `outline` for a whole-number target.
    ///
    /// - Parameters:
    ///   - target: The target zone, 1 to 5.
    ///   - outline: The ring's outline.
    /// - Returns: Six spans, by zone number.
    public static func spans(target: Int, outline: Outline) -> [Span] {
        let target = min(max(target, 1), 5)
        var spans = [Span](repeating: Span(start: 0, end: 0), count: 6)
        let total = outline.totalLength
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
    ///   - outline: The ring's outline.
    public static func spans(target: Double, outline: Outline) -> [Span] {
        let clamped = min(max(target, 1), 5)
        let low = Int(clamped.rounded(.down))
        let high = min(low + 1, 5)
        let fraction = clamped - Double(low)
        let a = spans(target: low, outline: outline)
        guard fraction > 0 else { return a }
        let b = spans(target: high, outline: outline)
        return (0...5).map { zone in
            Span(
                start: a[zone].start + (b[zone].start - a[zone].start) * fraction,
                end: a[zone].end + (b[zone].end - a[zone].end) * fraction)
        }
    }

    /// The distance along the outline of a position along the zones (see
    /// ``ZoneBands/position(forHeartRate:)``): inside its zone's span, by how far through the zone it is.
    ///
    /// - Parameters:
    ///   - position: Where the heart rate is along the zones, 0 to 6.
    ///   - spans: The zones' spans, from `spans(target:outline:)`.
    public static func distance(forPosition position: Double, in spans: [Span]) -> Double {
        let position = min(max(position, 0), 6)
        let zone = min(Int(position.rounded(.down)), 5)
        let span = spans[zone]
        return span.start + (position - Double(zone)) * span.length
    }
}
