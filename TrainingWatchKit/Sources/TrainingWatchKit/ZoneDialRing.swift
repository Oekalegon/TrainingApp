import SwiftUI
import TrainingCore

/// The ring of the zone dial (WATCH-118): six sectors round the screen's edge, zone 0 (below zone
/// 1, grey) and the five zones in their colours, with the target zone's sector centred on the top
/// and bright and the others in a darker shade, and a triangle just inside the ring pointing at where
/// the heart rate is. Fill the screen with it, ignoring the safe area, and put the text on top.
///
/// Both numbers animate, so a new target turns the ring and the triangle glides with the heart
/// rate. The geometry is `ZoneDial`.
public struct ZoneDialRing: View, @preconcurrency Animatable {
    /// The zone at the top, 1 to 5. Between two zones while the ring turns.
    public var target: Double
    /// Where the heart rate is along the zones, 0 to 6 (``ZoneBands/position(forHeartRate:)``).
    public var position: Double
    /// Whether the triangle shows: not without a heart-rate reading.
    public var showsMarker: Bool
    /// Whether the target's sector is bright. Off for a step with no heart-rate target, when the
    /// ring only shows which zone the heart rate is in.
    public var highlightsTarget: Bool
    public var lineWidth: Double
    /// The screen's corner radius, which the ring follows.
    public var cornerRadius: Double

    public var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(target, position) }
        set { (target, position) = (newValue.first, newValue.second) }
    }

    public init(
        target: Double, position: Double, showsMarker: Bool = true, highlightsTarget: Bool = true,
        lineWidth: Double = 9, cornerRadius: Double = 52
    ) {
        self.target = target
        self.position = position
        self.showsMarker = showsMarker
        self.highlightsTarget = highlightsTarget
        self.lineWidth = lineWidth
        self.cornerRadius = cornerRadius
    }

    /// The colour of a sector: grey below zone 1, otherwise the zone's own.
    static func color(ofZone zone: Int) -> Color {
        HeartRateZone(rawValue: zone)?.zoneColor ?? .gray
    }

    public var body: some View {
        Canvas { context, size in
            // The ring is drawn on the centre line of its stroke, half a stroke in from the edge.
            let ring = CGSize(width: size.width - lineWidth, height: size.height - lineWidth)
            let radius = max(cornerRadius - lineWidth / 2, 0)
            let origin = CGPoint(x: lineWidth / 2, y: lineWidth / 2)
            func point(_ angle: Double) -> (point: CGPoint, outward: Double) {
                let edge = ZoneDial.edgePoint(atAngle: angle, size: ring, cornerRadius: radius)
                return (CGPoint(x: edge.point.x + origin.x, y: edge.point.y + origin.y), edge.outward)
            }

            let bright = Int(target.rounded())
            for zone in 0...5 {
                let center = ZoneDial.sectorCenter(zone: zone, target: target)
                // A degree off each end, so the sectors read as separate.
                var path = Path()
                var angle = center - 29
                path.move(to: point(angle).point)
                while angle < center + 29 {
                    angle = min(angle + 2, center + 29)
                    path.addLine(to: point(angle).point)
                }
                let isBright = highlightsTarget && zone == bright
                context.stroke(
                    path, with: .color(Self.color(ofZone: zone).opacity(isBright ? 1 : 0.35)),
                    style: StrokeStyle(lineWidth: isBright ? lineWidth : lineWidth * 0.8, lineCap: .butt, lineJoin: .round))
            }

            guard showsMarker else { return }
            // A triangle just inside the ring, its tip towards the edge.
            let edge = point(ZoneDial.angle(forPosition: position, target: target))
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
