import SwiftUI

/// The run's altitude against distance (WATCH-149): a line coloured by how steep the ground is, from green on the
/// flat to red at 25 % or more, with the same colours fading to clear below it, a dot at the current position and a
/// faint grid with labels (`ElevationGridView`). Takes the points as ``RunStatsTracker`` keeps them (the whole run,
/// or the last 10 km) and scales them to fit, with a little room above and below so a flat run is a line in the
/// middle and not a line on the edge.
public struct ElevationProfileView: View {
    let points: [ElevationPoint]

    /// The height of the drawing: two units of a run screen.
    static let height = 56.0
    /// The room at the sides, so the dot at the current position isn't cut off.
    static let sidePadding = 4.0

    public init(points: [ElevationPoint]) { self.points = points }

    public var body: some View {
        // Worked out once: the screen redraws every second, and the line, the fade, the dot and the grid share it.
        let layout = ElevationProfileLayout(points)
        ZStack {
            if let layout {
                ElevationGridView(scale: layout.scale)
                let colors = LinearGradient(stops: layout.stops, startPoint: .leading, endPoint: .trailing)
                ElevationProfileShape(normalized: layout.normalized, closed: true)
                    .fill(colors.opacity(0.55))
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                ElevationProfileShape(normalized: layout.normalized, closed: false)
                    .stroke(colors, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                positionDot(layout)
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
        .accessibilityValue(ElevationProfileSummary.spoken(points, grades: layout?.grades ?? []))
    }

    /// A dot at the last point, the current position, in the colour the line has there.
    private func positionDot(_ layout: ElevationProfileLayout) -> some View {
        GeometryReader { proxy in
            if let last = layout.normalized.last {
                Circle()
                    .fill(layout.stops.last?.color ?? .green)
                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    .frame(width: 7, height: 7)
                    .position(x: last.x * proxy.size.width, y: proxy.size.height - last.y * proxy.size.height)
            }
        }
    }
}
