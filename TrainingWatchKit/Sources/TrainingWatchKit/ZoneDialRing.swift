import SwiftUI
import TrainingCore

/// The ring of the zone dial (WATCH-118): a circle like a gauge, open at the bottom, starting at the
/// lower left and running clockwise over the top. The target zone's arc is centred on the top and
/// bright, the lower zones are on the left and the higher ones on the right in a darker shade of their
/// colours, and a triangle just inside the ring points at where the heart rate is. Fill the screen with it, ignoring the safe area, and put the text on top.
///
/// Both numbers animate, so a new target moves the zones into their new places and the triangle
/// glides with the heart rate. The geometry is `ZoneDial`.
public struct ZoneDialRing: View, @preconcurrency Animatable {
    /// The zone on top, 1 to 5. Between two zones while the ring changes over.
    public var target: Double
    /// Where the heart rate is along the zones, 0 to 6 (``ZoneBands/position(forHeartRate:)``).
    public var position: Double
    /// Whether the triangle shows: not without a heart-rate reading.
    public var showsMarker: Bool
    /// Whether the target's sector is bright. Off for a step with no heart-rate target, when the
    /// ring only shows which zone the heart rate is in.
    public var highlightsTarget: Bool
    /// The target as a stretch along the zones (``StepHeartRateTarget/positions(in:)``). The part of
    /// the target zone's sector outside it is drawn in the darker shade; `nil` makes the whole zone bright.
    public var targetRange: ClosedRange<Double>?
    public var lineWidth: Double
    /// The angle left open at the bottom, in degrees.
    public var gapAngle: Double
    /// Space kept free at the top, so the circle starts below the watch's clock, which sits in the
    /// upper right corner and would reach into a circle that went all the way up.
    public var topInset: Double

    public var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(target, position) }
        set { (target, position) = (newValue.first, newValue.second) }
    }

    public init(
        target: Double, position: Double, showsMarker: Bool = true, highlightsTarget: Bool = true,
        targetRange: ClosedRange<Double>? = nil, lineWidth: Double = 10, gapAngle: Double = 76,
        topInset: Double = 0
    ) {
        self.target = target
        self.position = position
        self.showsMarker = showsMarker
        self.highlightsTarget = highlightsTarget
        self.targetRange = targetRange
        self.lineWidth = lineWidth
        self.gapAngle = gapAngle
        self.topInset = topInset
    }

    /// The colour of a sector: grey below zone 1, otherwise the zone's own.
    static func color(ofZone zone: Int) -> Color {
        HeartRateZone(rawValue: zone)?.zoneColor ?? .gray
    }

    public var body: some View {
        Canvas { context, size in
            // The circle fits the screen's width and the height below the clock, with the ring's
            // stroke inside it; the ring is drawn on the centre line of its stroke.
            let radius = max(min(size.width, size.height - topInset) / 2 - lineWidth / 2 - 1, 0)
            let outline = ZoneDial.Outline(
                center: CGPoint(x: size.width / 2, y: topInset + lineWidth / 2 + 1 + radius),
                radius: radius, gapAngle: gapAngle)
            func point(_ distance: Double) -> (point: CGPoint, outward: Double) { outline.point(at: distance) }

            let spans = ZoneDial.spans(target: target, outline: outline)
            let bright = Int(target.rounded())
            func stroke(_ zone: Int, from start: Double, to end: Double, bright isBright: Bool) {
                // A point or so off each end, so the sectors read as separate.
                guard end > start else { return }
                var path = Path()
                path.move(to: point(start).point)
                let steps = max(Int(((end - start) / 3).rounded(.up)), 1)
                for step in 1...steps { path.addLine(to: point(start + (end - start) * Double(step) / Double(steps)).point) }
                context.stroke(
                    path, with: .color(Self.color(ofZone: zone).opacity(isBright ? 1 : 0.4)),
                    style: StrokeStyle(lineWidth: isBright ? lineWidth : lineWidth * 0.8, lineCap: .butt, lineJoin: .round))
            }
            for zone in 0...5 {
                let span = spans[zone]
                let start = span.start + 1.5, end = span.end - 1.5
                guard highlightsTarget, zone == bright else {
                    stroke(zone, from: start, to: end, bright: false)
                    continue
                }
                // The target zone: all of it bright, or, for a target that is part of the zone, the
                // part that is the target over the whole zone in the darker shade.
                if let targetRange {
                    stroke(zone, from: start, to: end, bright: false)
                    let low = min(max(targetRange.lowerBound - Double(zone), 0), 1)
                    let high = min(max(targetRange.upperBound - Double(zone), 0), 1)
                    stroke(zone, from: start + (end - start) * low, to: start + (end - start) * high, bright: true)
                } else {
                    stroke(zone, from: start, to: end, bright: true)
                }
            }

            guard showsMarker else { return }
            // A triangle just inside the ring, its tip towards the edge.
            let edge = point(ZoneDial.distance(forPosition: position, in: spans))
            let outward = edge.outward * .pi / 180
            let nx = sin(outward), ny = -cos(outward)
            let tipDistance = lineWidth / 2 + 3
            let height = lineWidth * 1.6
            let tip = CGPoint(x: edge.point.x - nx * tipDistance, y: edge.point.y - ny * tipDistance)
            let baseCenter = CGPoint(x: tip.x - nx * height, y: tip.y - ny * height)
            let half = height * 0.65
            var triangle = Path()
            triangle.move(to: tip)
            triangle.addLine(to: CGPoint(x: baseCenter.x + ny * half, y: baseCenter.y - nx * half))
            triangle.addLine(to: CGPoint(x: baseCenter.x - ny * half, y: baseCenter.y + nx * half))
            triangle.closeSubpath()
            context.fill(triangle, with: .color(.white))
        }
        .accessibilityHidden(true)
    }
}
