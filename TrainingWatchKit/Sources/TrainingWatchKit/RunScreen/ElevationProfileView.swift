import SwiftUI

/// The run's altitude against distance (WATCH-149): a green line with a green fade to clear below it. Takes the
/// profile as ``RunStatsTracker`` keeps it and scales it to fit, with a little room above and below so a flat run
/// is a line in the middle and not a line on the edge.
public struct ElevationProfileView: View {
    let points: [ElevationPoint]

    /// The height of the drawing: two units of a run screen.
    static let height = 56.0
    static let lineColor = Color.green

    public init(points: [ElevationPoint]) { self.points = points }

    public var body: some View {
        ZStack {
            if points.count >= 2 {
                ElevationProfileShape(points: points, closed: true)
                    .fill(LinearGradient(
                        colors: [Self.lineColor.opacity(0.55), Self.lineColor.opacity(0)],
                        startPoint: .top, endPoint: .bottom))
                ElevationProfileShape(points: points, closed: false)
                    .stroke(Self.lineColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            } else {
                Text("No altitude yet")
                    .font(RunMetricStyle.captionFont).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: Self.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Elevation profile")
        .accessibilityValue(Self.spoken(points))
    }

    /// "Climbed 34 metres, now 47 metres above sea level", or "no altitude yet".
    static func spoken(_ points: [ElevationPoint]) -> String {
        guard let first = points.first, let last = points.last, points.count >= 2 else { return "no altitude yet" }
        let change = Int((last.altitude - first.altitude).rounded())
        let direction = change == 0 ? "no change in altitude" : "\(abs(change)) metres " + (change > 0 ? "higher" : "lower") + " than the start"
        return "\(direction), now \(Int(last.altitude.rounded())) metres"
    }
}

/// The profile as a path in its rect: the line, or with `closed` the area under it down to the bottom edge.
struct ElevationProfileShape: Shape {
    let points: [ElevationPoint]
    let closed: Bool

    /// The room kept above the highest and below the lowest point, as a share of the height.
    static let margin = 0.12
    /// The least altitude range (metres) the height stands for, so a flat stretch with GPS noise isn't blown up to
    /// look like a climb.
    static let minimumRange = 10.0

    /// Each point as a fraction of the width (0 at the start of the run, 1 now) and the height (0 at the bottom).
    static func normalized(_ points: [ElevationPoint]) -> [CGPoint] {
        guard let first = points.first, let last = points.last, points.count >= 2 else { return [] }
        let length = max(last.meters - first.meters, 1)
        let low = points.map(\.altitude).min() ?? 0
        let high = points.map(\.altitude).max() ?? 0
        let range = max(high - low, minimumRange)
        // A range wider than the climb is centred on it.
        let base = low - (range - (high - low)) / 2
        return points.map { point in
            CGPoint(
                x: (point.meters - first.meters) / length,
                y: margin + (1 - 2 * margin) * (point.altitude - base) / range)
        }
    }

    func path(in rect: CGRect) -> Path {
        let normalized = Self.normalized(points)
        guard normalized.count >= 2 else { return Path() }
        let mapped = normalized.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.maxY - $0.y * rect.height) }
        var path = Path()
        path.move(to: closed ? CGPoint(x: mapped[0].x, y: rect.maxY) : mapped[0])
        if closed { path.addLine(to: mapped[0]) }
        for point in mapped.dropFirst() { path.addLine(to: point) }
        if closed {
            path.addLine(to: CGPoint(x: mapped[mapped.count - 1].x, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}
