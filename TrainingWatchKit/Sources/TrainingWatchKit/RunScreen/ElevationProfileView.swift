import SwiftUI

/// The run's altitude against distance (WATCH-149): a line coloured by how steep the ground is, from green on the
/// flat to red at 25 % or more, with the same colours fading to clear below it, and a dot at the current position.
/// Takes the points as ``RunStatsTracker`` keeps them (the whole run, or the last 10 km) and scales them to fit, with
/// a little room above and below so a flat run is a line in the middle and not a line on the edge.
public struct ElevationProfileView: View {
    let points: [ElevationPoint]

    /// The height of the drawing: two units of a run screen.
    static let height = 56.0
    /// The room at the sides, so the dot at the current position isn't cut off.
    static let sidePadding = 4.0

    public init(points: [ElevationPoint]) { self.points = points }

    public var body: some View {
        ZStack {
            if points.count >= 2 {
                let colors = ElevationGrade.gradient(for: points)
                ElevationProfileShape(points: points, closed: true)
                    .fill(LinearGradient(stops: colors, startPoint: .leading, endPoint: .trailing).opacity(0.55))
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                ElevationProfileShape(points: points, closed: false)
                    .stroke(
                        LinearGradient(stops: colors, startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                positionDot(colors: colors)
            } else {
                Text("No altitude yet")
                    .font(RunMetricStyle.captionFont).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Self.sidePadding)
        .frame(height: Self.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Elevation profile")
        .accessibilityValue(Self.spoken(points))
    }

    /// A dot at the last point, the current position, in the colour the line has there.
    private func positionDot(colors: [Gradient.Stop]) -> some View {
        GeometryReader { proxy in
            if let last = ElevationProfileShape.normalized(points).last {
                Circle()
                    .fill(colors.last?.color ?? .green)
                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    .frame(width: 7, height: 7)
                    .position(x: last.x * proxy.size.width, y: proxy.size.height - last.y * proxy.size.height)
            }
        }
    }

    /// "47 metres, 12 metres higher than the start of the graph", or "no altitude yet".
    static func spoken(_ points: [ElevationPoint]) -> String {
        guard let first = points.first, let last = points.last, points.count >= 2 else { return "no altitude yet" }
        let change = Int((last.altitude - first.altitude).rounded())
        let direction = change == 0 ? "no change in altitude" : "\(abs(change)) metres " + (change > 0 ? "higher" : "lower") + " than the start of the graph"
        return "\(direction), now \(Int(last.altitude.rounded())) metres"
    }
}

/// How steep the ground is along the profile, and the colour that says so.
enum ElevationGrade {
    /// The grade at a point is taken between the points at least this many metres before and after it, so GPS noise
    /// between close points isn't drawn as a steep stretch.
    static let window = 50.0
    /// The grade (percent, up or down) at which the line is fully red.
    static let redGrade = 25.0

    /// The grade in percent at each point (positive uphill).
    static func grades(of points: [ElevationPoint]) -> [Double] {
        points.indices.map { index in
            let here = points[index].meters
            var low = index
            while low > 0, here - points[low].meters < window { low -= 1 }
            var high = index
            while high < points.count - 1, points[high].meters - here < window { high += 1 }
            let run = points[high].meters - points[low].meters
            return run > 0 ? (points[high].altitude - points[low].altitude) / run * 100 : 0
        }
    }

    /// The hue (0 red … 1/3 green) for a grade: green on the flat, through yellow and orange, to red at ``redGrade``
    /// and steeper, whichever way the ground slopes.
    static func hue(forGrade grade: Double) -> Double {
        (1.0 / 3) * (1 - min(abs(grade) / redGrade, 1))
    }

    static func color(forGrade grade: Double) -> Color {
        Color(hue: hue(forGrade: grade), saturation: 0.85, brightness: 0.95)
    }

    /// The stops of a left-to-right gradient that gives each point its grade's colour at its place along the width.
    static func gradient(for points: [ElevationPoint]) -> [Gradient.Stop] {
        let positions = ElevationProfileShape.normalized(points).map(\.x)
        return zip(positions, grades(of: points)).map { Gradient.Stop(color: color(forGrade: $1), location: $0) }
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

    /// Each point as a fraction of the width (0 at the first point, 1 at the last) and the height (0 at the bottom).
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
