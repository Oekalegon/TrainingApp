import SwiftUI

/// The grid with its labels inside the graph (WATCH-149): the altitude at the left end of each horizontal line, the
/// distance at the foot of each vertical one. Faint, so the profile stays what the eye follows.
struct ElevationGridView: View {
    let scale: ElevationScale

    private static let lineColor = Color.white.opacity(0.22)
    private static let labelColor = Color.white.opacity(0.55)
    private static let labelWidth = 60.0

    var body: some View {
        GeometryReader { proxy in
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
                    let fitsRight = ElevationGrid.labelFitsRight(lineAt: x, width: width)
                    label(ElevationGrid.distanceLabel(meters), alignment: fitsRight ? .leading : .trailing)
                        .position(x: fitsRight ? x + 2 + Self.labelWidth / 2 : x - 2 - Self.labelWidth / 2, y: height - 6)
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
            // A fixed frame aligned to one side, so `position` puts the text's end at the line and not its middle.
            .frame(width: Self.labelWidth, alignment: alignment)
    }
}
