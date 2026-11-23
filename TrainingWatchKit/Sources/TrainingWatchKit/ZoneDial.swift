import CoreGraphics
import Foundation

/// The geometry of the zone dial (WATCH-118): a ring along the whole edge of the screen with a gap in
/// the upper right corner, where the watch's clock is. It starts on the right side just below the
/// gap, runs clockwise down the right side, along the bottom, up the left side and along the top to
/// the gap, like a gauge. Zone 0 (below zone 1) comes first and zone 5 last.
///
/// The zones sit along it by their place against the target zone, in three stretches:
/// - the zones **below** the target first, with zone 0 half the size of the others (the whole
///   stretch when the target is zone 1);
/// - the **target zone**, a stretch of its own;
/// - the zones **above** it, equal, ending at the gap.
///
/// A new target lays the ring out again. ``spans(target:outline:)`` blends two layouts when the
/// target is between two zones, so the change can be animated.
///
/// Pure arithmetic, so it can be tested without a screen; `ZoneDialRing` draws it.
public enum ZoneDial {
    /// The share of the ring the zones below the target, the target and the zones above it take.
    /// A stretch with no zones in it (nothing above a zone 5 target) is left empty.
    public static let shares = (below: 0.35, target: 0.30, above: 0.35)

    /// The ring's outline: the screen's rounded rectangle without a gap in its upper right corner,
    /// measured along its length from the start, on the right side below the gap, clockwise.
    public struct Outline: Sendable {
        public let size: CGSize
        public let cornerRadius: Double
        /// How far down the right side the ring starts: the height of the gap.
        public let gapHeight: Double
        /// How far from the right the top ends: the width of the gap.
        public let gapWidth: Double
        /// The length of the whole outline.
        public let totalLength: Double

        private enum Segment {
            case line(from: CGPoint, to: CGPoint, outward: Double, length: Double)
            case arc(center: CGPoint, from: Double, length: Double)
        }
        private let segments: [Segment]

        /// - Parameters:
        ///   - size: The size of the rounded rectangle.
        ///   - cornerRadius: The radius of its corners, at most half its shorter side.
        ///   - gapWidth: The width of the gap at the top right.
        ///   - gapHeight: The height of the gap at the top right.
        public init(size: CGSize, cornerRadius: Double, gapWidth: Double = 0, gapHeight: Double = 0) {
            self.size = size
            let width = Double(size.width), height = Double(size.height)
            let r = min(max(cornerRadius, 0), width / 2, height / 2)
            self.cornerRadius = r
            // The gap can't reach past the bottom right and top left corners' curves.
            let gapY = min(max(gapHeight, 0), height - r)
            let gapX = min(max(gapWidth, 0), width - r)
            self.gapHeight = gapY
            self.gapWidth = gapX
            let arc = r * .pi / 2
            var list: [Segment] = []
            func line(_ from: CGPoint, _ to: CGPoint, _ outward: Double) {
                let length = hypot(Double(to.x - from.x), Double(to.y - from.y))
                if length > 0 { list.append(.line(from: from, to: to, outward: outward, length: length)) }
            }
            func corner(_ center: CGPoint, _ from: Double, length: Double? = nil) {
                let length = length ?? arc
                if length > 0 { list.append(.arc(center: center, from: from, length: length)) }
            }
            // Down the right side, round the bottom right corner, along the bottom, round the
            // bottom left corner, up the left side, round the top left corner, along the top to the gap.
            // A gap shorter than the corner's radius cuts into the top right corner's curve: the ring
            // then starts part-way round it, instead of on a straight line outside the rounded screen.
            let topRight = CGPoint(x: width - r, y: r)
            if gapY < r, r > 0 {
                let start = acos((r - gapY) / r)
                corner(topRight, start * 180 / .pi, length: r * (.pi / 2 - start))
                line(CGPoint(x: width, y: r), CGPoint(x: width, y: height - r), 90)
            } else {
                line(CGPoint(x: width, y: gapY), CGPoint(x: width, y: height - r), 90)
            }
            corner(CGPoint(x: width - r, y: height - r), 90)
            line(CGPoint(x: width - r, y: height), CGPoint(x: r, y: height), 180)
            corner(CGPoint(x: r, y: height - r), 180)
            line(CGPoint(x: 0, y: height - r), CGPoint(x: 0, y: r), 270)
            corner(CGPoint(x: r, y: r), 270)
            if gapX < r, r > 0 {
                // The gap is narrower than the corner's radius: the top runs on round the corner's curve.
                line(CGPoint(x: r, y: 0), CGPoint(x: width - r, y: 0), 0)
                let end = asin((r - gapX) / r)
                corner(topRight, 0, length: r * end)
            } else {
                line(CGPoint(x: r, y: 0), CGPoint(x: width - gapX, y: 0), 0)
            }
            segments = list
            totalLength = list.reduce(0) { total, segment in
                switch segment {
                case .line(_, _, _, let length): total + length
                case .arc(_, _, let length): total + length
                }
            }
        }

        /// The point at `distance` along the outline, with the angle its outward normal points at
        /// (degrees clockwise from the top, so the left side faces 270 and the right side 90).
        /// A distance beyond the ends is held at the end.
        public func point(at distance: Double) -> (point: CGPoint, outward: Double) {
            var d = min(max(distance, 0), totalLength)
            for segment in segments {
                switch segment {
                case .line(let from, let to, let outward, let length):
                    if d <= length {
                        let f = length > 0 ? d / length : 0
                        return (CGPoint(x: from.x + (to.x - from.x) * f, y: from.y + (to.y - from.y) * f), outward)
                    }
                    d -= length
                case .arc(let center, let from, let length):
                    if d <= length {
                        let r = cornerRadius
                        let angle = from + (r > 0 ? d / r * 180 / .pi : 0)
                        let radians = angle * .pi / 180
                        return (CGPoint(x: Double(center.x) + r * sin(radians), y: Double(center.y) - r * cos(radians)), angle)
                    }
                    d -= length
                }
            }
            // Only reached with no segments at all.
            return (.zero, 0)
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
