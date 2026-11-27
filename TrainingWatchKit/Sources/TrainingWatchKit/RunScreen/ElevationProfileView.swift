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
                ElevationGridView(points: points)
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
        guard let scale = ElevationScale(points) else { return [] }
        return points.map { CGPoint(x: scale.x(meters: $0.meters), y: scale.y(altitude: $0.altitude)) }
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

/// How the profile's distance and altitude map onto the drawing: shared by the line and the grid, so a grid line
/// sits exactly where the altitude or distance it names is drawn.
struct ElevationScale {
    let startMeters: Double
    let length: Double
    /// The altitude at the bottom of the drawn range (above the bottom margin) and the metres the range spans.
    let baseAltitude: Double
    let range: Double

    init?(_ points: [ElevationPoint]) {
        guard let first = points.first, let last = points.last, points.count >= 2 else { return nil }
        startMeters = first.meters
        length = max(last.meters - first.meters, 1)
        let low = points.map(\.altitude).min() ?? 0
        let high = points.map(\.altitude).max() ?? 0
        range = max(high - low, ElevationProfileShape.minimumRange)
        // A range wider than the climb is centred on it.
        baseAltitude = low - (range - (high - low)) / 2
    }

    func x(meters: Double) -> Double { (meters - startMeters) / length }

    func y(altitude: Double) -> Double {
        let margin = ElevationProfileShape.margin
        return margin + (1 - 2 * margin) * (altitude - baseAltitude) / range
    }
}

/// The horizontal (altitude) and vertical (distance) lines drawn behind the profile, at round values.
enum ElevationGrid {
    /// The least number of lines wanted either way is none; the most is about this many.
    static let altitudeLines = 3.0
    static let distanceLines = 4.0

    /// The smallest 1, 2 or 5 times a power of ten that is at least `value`.
    static func niceStep(atLeast value: Double) -> Double {
        guard value > 0 else { return 1 }
        let magnitude = pow(10, floor(log10(value)))
        return [1.0, 2, 5, 10].map { $0 * magnitude }.first { $0 >= value * (1 - 1e-9) } ?? 10 * magnitude
    }

    /// The altitudes (metres) of the horizontal lines: multiples of a round step inside the drawn range.
    static func altitudes(_ scale: ElevationScale) -> [Double] {
        multiples(of: niceStep(atLeast: scale.range / altitudeLines), from: scale.baseAltitude, to: scale.baseAltitude + scale.range)
    }

    /// The distances (metres, from the start of the run) of the vertical lines: multiples of a round step inside the graph.
    static func distances(_ scale: ElevationScale) -> [Double] {
        multiples(of: niceStep(atLeast: scale.length / distanceLines), from: scale.startMeters, to: scale.startMeters + scale.length)
    }

    /// The multiples of `step` strictly between `low` and `high`, so none sits on the edge of the drawing.
    private static func multiples(of step: Double, from low: Double, to high: Double) -> [Double] {
        var result: [Double] = []
        var value = (low / step).rounded(.down) * step + step
        while value < high - step * 0.01 {
            result.append(value)
            value += step
        }
        return result
    }

    static func altitudeLabel(_ meters: Double) -> String { "\(Int(meters.rounded())) m" }

    /// "2 km", or "0.5 km" for a step under a kilometre.
    static func distanceLabel(_ meters: Double) -> String {
        let km = meters / 1000
        return (km == km.rounded() ? "\(Int(km))" : String(format: "%.1f", km)) + " km"
    }
}

/// The grid with its labels inside the graph: the altitude at the left end of each horizontal line, the distance at
/// the foot of each vertical one. Faint, so the profile stays what the eye follows.
struct ElevationGridView: View {
    let points: [ElevationPoint]

    private static let lineColor = Color.white.opacity(0.22)
    private static let labelColor = Color.white.opacity(0.55)

    var body: some View {
        GeometryReader { proxy in
            if let scale = ElevationScale(points) {
                let width = proxy.size.width
                let height = proxy.size.height
                ZStack(alignment: .topLeading) {
                    ForEach(ElevationGrid.altitudes(scale), id: \.self) { altitude in
                        let y = height - scale.y(altitude: altitude) * height
                        line(from: CGPoint(x: 0, y: y), to: CGPoint(x: width, y: y))
                        label(ElevationGrid.altitudeLabel(altitude))
                            .position(x: 2 + Self.labelWidth / 2, y: y - 6)
                    }
                    ForEach(ElevationGrid.distances(scale), id: \.self) { meters in
                        let x = scale.x(meters: meters) * width
                        line(from: CGPoint(x: x, y: 0), to: CGPoint(x: x, y: height))
                        // At the right end the label would be cut off: it goes to the left of the line instead.
                        let fitsRight = x + 2 + Self.textRoom <= width
                        label(ElevationGrid.distanceLabel(meters), alignment: fitsRight ? .leading : .trailing)
                            .position(x: fitsRight ? x + 2 + Self.labelWidth / 2 : x - 2 - Self.labelWidth / 2, y: height - 6)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func line(from start: CGPoint, to end: CGPoint) -> some View {
        Path { path in
            path.move(to: start)
            path.addLine(to: end)
        }
        .stroke(Self.lineColor, style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
    }

    private func label(_ text: String, alignment: Alignment = .leading) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(Self.labelColor)
            .lineLimit(1).fixedSize()
            // A fixed, leading-aligned frame, so `position` puts the text's left end at the line and not its middle.
            .frame(width: Self.labelWidth, alignment: alignment)
    }

    private static let labelWidth = 60.0
    /// The room a label such as "10.5 km" needs at 9 points.
    private static let textRoom = 34.0
}
