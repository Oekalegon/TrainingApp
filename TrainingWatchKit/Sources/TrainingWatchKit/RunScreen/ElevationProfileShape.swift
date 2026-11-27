import SwiftUI

/// The profile as a path in its rect (WATCH-149): the line, or with `closed` the area under it down to the bottom edge.
struct ElevationProfileShape: Shape {
    /// The points as `ElevationProfileLayout.normalized` has them: fractions of the width and height, 0 at the bottom.
    let normalized: [CGPoint]
    let closed: Bool

    func path(in rect: CGRect) -> Path {
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
