import CoreGraphics
import Foundation

/// The geometry of the zone dial (WATCH-118): an open ring along the screen's edge that starts at the
/// bottom left, goes up the left side, across the top and down the right side to the bottom right,
/// leaving the bottom free. The zones sit along it by their place against the target zone:
///
/// - the **target zone** has the whole top, from one top corner to the other;
/// - the zones **below** it are squeezed into the left side, lowest first from the bottom, with zone
///   0 (below zone 1) half the size of the others (the whole side when the target is zone 1);
/// - the zones **above** it are on the right side, the one just above the target at the top.
///
/// A new target re-lays the ring. The zones move to their new places with ``spans(target:outline:)``
/// blending two layouts when the target is between two zones, so the change can be animated.
///
/// Pure arithmetic, so it can be tested without a screen; `ZoneDialRing` draws it.
public enum ZoneDial {
    /// The ring's outline: the screen's rounded rectangle without its bottom edge, measured along
    /// its length, from the start of the bottom edge on the left to its end on the right.
    public struct Outline: Sendable, Hashable {
        public let size: CGSize
        public let cornerRadius: Double
        /// The length of the left side, with the bottom left corner: from the start to the top left corner.
        public let leftLength: Double
        /// The length of the top, with both top corners.
        public let topLength: Double
        /// The length of the right side, with the bottom right corner.
        public let rightLength: Double
        public var totalLength: Double { leftLength + topLength + rightLength }

        /// - Parameters:
        ///   - size: The size of the rounded rectangle.
        ///   - cornerRadius: The radius of its corners, at most half its shorter side.
        public init(size: CGSize, cornerRadius: Double) {
            self.size = size
            let radius = min(max(cornerRadius, 0), Double(size.width) / 2, Double(size.height) / 2)
            self.cornerRadius = radius
            let arc = radius * .pi / 2
            leftLength = arc + (Double(size.height) - 2 * radius)
            topLength = 2 * arc + (Double(size.width) - 2 * radius)
            rightLength = (Double(size.height) - 2 * radius) + arc
        }

        /// The point at `distance` along the outline, with the angle its outward normal points at
        /// (degrees clockwise from the top, so the left side faces 270 and the right side 90).
        /// A distance beyond the ends is held at the end.
        public func point(at distance: Double) -> (point: CGPoint, outward: Double) {
            let width = Double(size.width), height = Double(size.height), r = cornerRadius
            let arc = r * .pi / 2
            let side = height - 2 * r
            let top = width - 2 * r
            var d = min(max(distance, 0), totalLength)

            func onArc(center: CGPoint, from: Double, along: Double) -> (CGPoint, Double) {
                // `along` is the distance along the arc; the angle turns by along / r radians.
                let angle = from + (r > 0 ? along / r * 180 / .pi : 0)
                let radians = angle * .pi / 180
                return (CGPoint(x: Double(center.x) + r * sin(radians), y: Double(center.y) - r * cos(radians)), angle)
            }
            // Bottom left corner, from the bottom edge up to the left side.
            if d <= arc {
                let (p, a) = onArc(center: CGPoint(x: r, y: height - r), from: 180, along: d)
                return (p, a)
            }
            d -= arc
            if d <= side { return (CGPoint(x: 0, y: height - r - d), 270) }
            d -= side
            if d <= arc {
                let (p, a) = onArc(center: CGPoint(x: r, y: r), from: 270, along: d)
                return (p, a)
            }
            d -= arc
            if d <= top { return (CGPoint(x: r + d, y: 0), 0) }
            d -= top
            if d <= arc {
                let (p, a) = onArc(center: CGPoint(x: width - r, y: r), from: 0, along: d)
                return (p, a)
            }
            d -= arc
            if d <= side { return (CGPoint(x: width, y: r + d), 90) }
            d -= side
            let (p, a) = onArc(center: CGPoint(x: width - r, y: height - r), from: 90, along: min(d, arc))
            return (p, a)
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
        // Left: zone 0, half a size unless it is alone, then the zones up to the target.
        let weights = (0..<target).map { zone in zone == 0 && target > 1 ? 0.5 : 1.0 }
        let total = weights.reduce(0, +)
        var cursor = 0.0
        for zone in 0..<target {
            let length = outline.leftLength * weights[zone] / total
            spans[zone] = Span(start: cursor, end: cursor + length)
            cursor += length
        }
        // The whole top.
        spans[target] = Span(start: outline.leftLength, end: outline.leftLength + outline.topLength)
        // Right: the zones above the target, equal, the nearest at the top.
        let above = 5 - target
        if above > 0 {
            let length = outline.rightLength / Double(above)
            for (index, zone) in ((target + 1)...5).enumerated() {
                let start = outline.leftLength + outline.topLength + Double(index) * length
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
