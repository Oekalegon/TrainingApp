import SwiftUI
import TrainingCore

/// The bar of the zone dial (WATCH-118): all the zones on one horizontal line, lowest on the left,
/// the target zone bright in the middle and the others in a darker shade of their colours, with a
/// small triangle above the line pointing down and one under it pointing up, both at where the heart rate is. The geometry is `ZoneDial`.
///
/// Both numbers animate, so a new target moves the zones into their new places and the triangle
/// glides with the heart rate.
public struct ZoneDialBar: View, @preconcurrency Animatable {
    /// The target zone, 1 to 5. Between two zones while the bar changes over.
    public var target: Double
    /// Where the heart rate is along the zones, 0 to 6 (``ZoneBands/position(forHeartRate:)``).
    public var position: Double
    /// Whether the triangle shows: not without a heart-rate reading.
    public var showsMarker: Bool
    /// Whether the target's zone is bright. Off for a step with no heart-rate target, when the bar
    /// only shows which zone the heart rate is in.
    public var highlightsTarget: Bool
    /// The target as a stretch along the zones (``StepHeartRateTarget/positions(in:)``). The part of
    /// the target zone outside it is drawn in the darker shade; `nil` makes the whole zone bright.
    public var targetRange: ClosedRange<Double>?
    /// The height of the bar. The triangles go above and under it, in a height of their own.
    public var barHeight: Double

    public var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(target, position) }
        set { (target, position) = (newValue.first, newValue.second) }
    }

    public init(
        target: Double, position: Double, showsMarker: Bool = true, highlightsTarget: Bool = true,
        targetRange: ClosedRange<Double>? = nil, barHeight: Double = 14
    ) {
        self.target = target
        self.position = position
        self.showsMarker = showsMarker
        self.highlightsTarget = highlightsTarget
        self.targetRange = targetRange
        self.barHeight = barHeight
    }

    /// The height of a marker triangle, its half width, and the gap between its tip and the bar.
    private static let markerHeight = 7.0, markerHalfWidth = 4.5, markerGap = 2.0
    /// The room above the bar for the upper triangle, which is also the room under it for the lower one.
    private static let markerRoom = markerHeight + markerGap

    /// The height the view needs: the bar and a triangle above and under it.
    public var height: Double { barHeight + 2 * Self.markerRoom }

    /// The colour of a zone: grey below zone 1, otherwise the zone's own.
    static func color(ofZone zone: Int) -> Color {
        HeartRateZone(rawValue: zone)?.zoneColor ?? .gray
    }

    public var body: some View {
        Canvas { context, size in
            // The upper triangle's room is above the bar: everything of the bar is drawn from there.
            context.translateBy(x: 0, y: Self.markerRoom)
            let spans = ZoneDial.spans(target: target, length: size.width)
            let bright = Int(target.rounded())
            func fill(_ zone: Int, from start: Double, to end: Double, bright isBright: Bool) {
                guard end > start else { return }
                // The darker shade is a bit thinner, so the bright part stands out in shape as well as colour.
                let thickness = isBright ? barHeight : barHeight * 0.7
                let rect = CGRect(x: start, y: (barHeight - thickness) / 2, width: end - start, height: thickness)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: min(3, rect.width / 2)),
                    with: .color(Self.color(ofZone: zone).opacity(isBright ? 1 : 0.4)))
            }
            for zone in 0...5 {
                let span = spans[zone]
                // A point or so off each end, so the zones read as separate.
                let start = span.start + 1, end = span.end - 1
                guard highlightsTarget, zone == bright else {
                    fill(zone, from: start, to: end, bright: false)
                    continue
                }
                // The target zone: all of it bright, or, for a target that is part of the zone, the
                // part that is the target bright over the whole zone in the darker shade.
                if let targetRange {
                    fill(zone, from: start, to: end, bright: false)
                    let low = min(max(targetRange.lowerBound - Double(zone), 0), 1)
                    let high = min(max(targetRange.upperBound - Double(zone), 0), 1)
                    fill(zone, from: start + (end - start) * low, to: start + (end - start) * high, bright: true)
                } else {
                    fill(zone, from: start, to: end, bright: true)
                }
            }

            guard showsMarker else { return }
            // A triangle above the bar pointing down and one under it pointing up, their tips at the
            // heart rate. Kept half a triangle in from the ends, so they aren't cut off at the edge of the view.
            let half = Self.markerHalfWidth
            let x = min(max(ZoneDial.distance(forPosition: position, in: spans), half), max(size.width - half, half))
            let above = barHeight + Self.markerGap
            var lower = Path()
            lower.move(to: CGPoint(x: x, y: above))
            lower.addLine(to: CGPoint(x: x - half, y: above + Self.markerHeight))
            lower.addLine(to: CGPoint(x: x + half, y: above + Self.markerHeight))
            lower.closeSubpath()
            var upper = Path()
            upper.move(to: CGPoint(x: x, y: -Self.markerGap))
            upper.addLine(to: CGPoint(x: x - half, y: -Self.markerGap - Self.markerHeight))
            upper.addLine(to: CGPoint(x: x + half, y: -Self.markerGap - Self.markerHeight))
            upper.closeSubpath()
            context.fill(lower, with: .color(.white))
            context.fill(upper, with: .color(.white))
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
